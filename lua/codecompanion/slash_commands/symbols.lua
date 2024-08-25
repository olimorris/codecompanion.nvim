---@diagnostic disable: undefined-field
local BaseSlashCommand = require("codecompanion.slash_commands").BaseSlashCommand
local api = vim.api
local cmp = require("cmp")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")

local SymbolsCommand = BaseSlashCommand:extend()

function SymbolsCommand:init(opts)
  opts = opts or {}
  BaseSlashCommand.init(self, opts)
  self.name = "symbols"
  self.description = "Insert current file symbols"
end

local function get_node_range(_, node)
  local start_row, start_col, end_row, end_col = node:range()
  return {
    start = { line = start_row, character = start_col },
    ["end"] = { line = end_row, character = end_col },
  }
end

local language_queries = {
  python = [[
    (function_definition name: (_) @func_name) @function
    (class_definition name: (_) @class_name) @class
    (module) @module
    ((identifier) @variable (#is-not? local))
  ]],
  lua = [[
    (function_declaration name: (_) @func_name) @function
    (function_definition name: (_) @func_name) @function
    (local_function name: (_) @func_name) @function
    (variable_declaration name: (_) @variable)
  ]],
  javascript = [[
    (function_declaration name: (_) @func_name) @function
    (class_declaration name: (_) @class_name) @class
    (method_definition name: (_) @method_name) @method
    (variable_declaration) @variable
  ]],
  go = [[
    (function_declaration name: (identifier) @func_name) @function
    (method_declaration name: (field_identifier) @method_name) @method
    (type_declaration
      (type_spec name: (type_identifier) @type_name) @type
    )
    (struct_type_declaration
      name: (type_identifier) @struct_name
    ) @struct
    (interface_type_declaration
      name: (type_identifier) @interface_name
    ) @interface
    (const_declaration
      (const_spec name: (identifier) @const_name)
    ) @const
    (var_declaration
      (var_spec name: (identifier) @var_name)
    ) @var
  ]],
  -- 添加更多语言的查询...
}

local function find_symbol_node(bufnr, symbol_name, start_line)
  local parser = vim.treesitter.get_parser(bufnr)
  local tree = parser:parse()[1]
  local root = tree:root()

  local lang = vim.bo[bufnr].filetype
  local query_string = language_queries[lang]
    or [[
    (function) @function
    (class) @class
    (variable) @variable
  ]]

  local query = vim.treesitter.query.parse(lang, query_string)

  for id, node in query:iter_captures(root, bufnr, start_line, -1) do
    local name = query.captures[id]
    if name:match("_name$") then
      if vim.treesitter.get_node_text(node, bufnr) == symbol_name then
        return node:parent()
      end
    elseif name == "variable" or name == "module" then
      if vim.treesitter.get_node_text(node, bufnr):match(symbol_name) then
        return node
      end
    end
  end
  return nil
end

local function get_symbol_range(bufnr, symbol)
  if symbol.range.start.line ~= symbol.range["end"].line then
    -- LSP provided a multi-line range, use it
    return symbol.range
  else
    -- LSP provided a single-line range, use Treesitter to find the full range
    local node = find_symbol_node(bufnr, symbol.name, symbol.range.start.line)
    if node then
      return get_node_range(bufnr, node)
    else
      -- Fallback to LSP range if Treesitter fails
      return symbol.range
    end
  end
end

local important_symbol_kinds = {
  [vim.lsp.protocol.SymbolKind.Class] = true,
  [vim.lsp.protocol.SymbolKind.Method] = true,
  [vim.lsp.protocol.SymbolKind.Constructor] = true,
  [vim.lsp.protocol.SymbolKind.Enum] = true,
  [vim.lsp.protocol.SymbolKind.Interface] = true,
  [vim.lsp.protocol.SymbolKind.Function] = true,
  [vim.lsp.protocol.SymbolKind.Constant] = true,
  [vim.lsp.protocol.SymbolKind.Object] = true,
  [vim.lsp.protocol.SymbolKind.Struct] = true,
  [vim.lsp.protocol.SymbolKind.Event] = true,
}

--- Complete file paths for the command.
--- @param params cmp.SourceCompletionApiParams
--- @param callback fun(response: CodeCompanion.SlashCommandCompletionResponse|nil)
---@diagnostic disable-next-line: unused-local
function SymbolsCommand:complete(params, callback)
  local chat = self.get_chat()
  if not chat then
    return callback()
  end

  local bufnr = chat.focus_bufnr
  local filepath = vim.fn.fnamemodify(api.nvim_buf_get_name(bufnr), ":.")

  vim.lsp.buf_request(
    bufnr,
    "textDocument/documentSymbol",
    { textDocument = vim.lsp.util.make_text_document_params(bufnr) },
    function(err, results, _, _)
      if err then
        log:warn("Error when requesting document symbols: %s", err)
        return callback()
      end

      local items = {}

      local function process_symbols(symbols, prefix)
        for _, symbol in ipairs(symbols) do
          if not important_symbol_kinds[symbol.kind] then
            goto continue
          end

          local full_name = prefix and (prefix .. "." .. symbol.name) or symbol.name
          local kind_name = vim.lsp.protocol.SymbolKind[symbol.kind] or "Unknown"
          local item = {
            label = full_name,
            kind = cmp.lsp.CompletionItemKind[kind_name] or cmp.lsp.CompletionItemKind.Text,
            slash_command_name = self.name,
            slash_command_args = {
              symbol = symbol,
              filepath = filepath,
              range = nil,
            },
          }

          local ok, range = pcall(get_symbol_range, bufnr, symbol)
          if ok then
            item.slash_command_args.range = range
          end

          table.insert(items, item)

          if symbol.children then
            process_symbols(symbol.children, full_name)
          end

          ::continue::
        end
      end

      process_symbols(results)

      return callback({ items = items, isIncomplete = false })
    end
  )
end

---Resolve completion item (optional). This is called right before the completion is about to be displayed.
---Useful for setting the text shown in the documentation window (`completion_item.documentation`).
---@param completion_item CodeCompanion.SlashCommandCompletionItem
---@param callback fun(completion_item: CodeCompanion.SlashCommandCompletionItem|nil)
function SymbolsCommand:resolve(completion_item, callback)
  local chat = self.get_chat()
  if not chat then
    return callback()
  end

  local symbol = completion_item.slash_command_args.symbol
  local filepath = completion_item.slash_command_args.filepath
  local range = completion_item.slash_command_args.range
  local kind_name = vim.lsp.protocol.SymbolKind[symbol.kind] or "Unknown"

  if range then
    local bufnr = chat.focus_bufnr

    local start_line = range.start.line
    local end_line = range["end"].line
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)
    local symbol_content = table.concat(lines, "\n")

    completion_item.documentation = {
      kind = require("cmp").lsp.MarkupKind.Markdown,
      value = string.format(
        "Symbols for %s:\n%s\nkind: %s - name: %s",
        filepath,
        symbol_content,
        kind_name,
        symbol.name
      ),
    }
  else
    completion_item.documentation = {
      kind = require("cmp").lsp.MarkupKind.Markdown,
      value = string.format("Symbols for %s:\n%s\nkind: %s - name: %s", filepath, "", kind_name, symbol.name),
    }
  end

  callback(completion_item)
end

return SymbolsCommand
