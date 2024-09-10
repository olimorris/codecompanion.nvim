local config = require("codecompanion").config

local log = require("codecompanion.utils.log")

---Queries can probably be solely taken from the amazing Aerial.nvim plugin:
---https://github.com/stevearc/aerial.nvim/blob/master/queries/python/aerial.scm
local Queries = {
  lua = [[
(function_declaration
  name: [
    (identifier)
    (dot_index_expression)
    (method_index_expression)
  ] @name
  (#set! "kind" "Function")) @symbol
]],
  python = [[
(function_definition
  name: (identifier) @name
  (#set! "kind" "Function")) @symbol

(class_definition
  name: (identifier) @name
  (#set! "kind" "Class")) @symbol
]],
  ruby = [[
; Module definitions
(module
  name: [
    (constant)
    (scope_resolution)
  ] @name
  (#set! "kind" "Module")) @symbol

; Class definitions
(class
  name: [
    (constant)
    (scope_resolution)
  ] @name
  (#set! "kind" "Class")) @symbol

(singleton_class
  value: (_) @name
  (#set! "kind" "Class")) @symbol

; Method definitions
(singleton_method
  object: [
    (constant)
    (self)
    (identifier)
  ] @receiver
  ([
    "."
    "::"
  ] @separator)?
  name: [
    (operator)
    (identifier)
  ] @name
  (#set! "kind" "Method")) @symbol

(body_statement
  [
    (_)
    ((identifier) @scope
      (#any-of? @scope "private" "protected" "public"))
  ]*
  .
  (method
    name: (_) @name
    (#set! "kind" "Method")) @symbol)
]],
}

---@class CodeCompanion.SlashCommandSymbols
local SlashCommandSymbols = {}

---@class CodeCompanion.SlashCommandSymbols
---@field Chat CodeCompanion.Chat The chat buffer
---@field config table The config of the slash command
---@field context table The context of the chat buffer from the completion menu
function SlashCommandSymbols.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommandSymbols })

  return self
end

---Execute the slash command
---@return nil
function SlashCommandSymbols:execute()
  if not config.opts.send_code and (self.config.opts and self.config.opts.contains_code) then
    return log:warn("Sending of code has been disabled")
  end

  local lang = self.Chat.context.filetype
  if not Queries[lang] then
    return log:warn("No query has been defined for my filetype (%s). Please make a PR for me...", lang)
  end

  local Chat = self.Chat
  local bufnr = self.Chat.context.bufnr
  local query = vim.treesitter.query.parse(lang, Queries[lang])

  local parser = vim.treesitter.get_parser(bufnr, lang)
  local tree = parser:parse()[1]

  local function get_ts_node(output_tbl, type, match)
    table.insert(
      output_tbl,
      string.format(" - %s %s", type, vim.trim(vim.treesitter.get_node_text(match.node, bufnr, match)))
    )
  end

  local kinds = {
    "Module",
    "Class",
    "Method",
    "Function",
  }

  local symbols = {}
  for _, matches, metadata in query:iter_matches(tree:root(), bufnr) do
    local match = vim.tbl_extend("force", {}, metadata)
    for id, node in pairs(matches) do
      match = vim.tbl_extend("keep", match, {
        [query.captures[id]] = {
          metadata = metadata[id],
          node = node,
        },
      })
    end

    local symbol_node = (match.symbol or {}).node

    if not symbol_node then
      goto continue
    end

    local name_match = match.name or {}
    local kind = match.kind

    if kind then
      for _, k in ipairs(kinds) do
        if kind == k then
          get_ts_node(symbols, k:lower(), name_match)
        end
      end
    end

    ::continue::
  end

  if #symbols ~= 0 then
    local content = table.concat(symbols, "\n")
    Chat:append_to_buf({ content = "[!Symbols]\n" })
    Chat:append_to_buf({
      content = string.format(
        "```txt\nFilename: %s\nFiletype: %s\n<symbols>\n%s\n</symbols>\n```\n",
        Chat.context.filename,
        Chat.context.filetype,
        content
      ),
    })
    Chat:fold_code()
  end
end

return SlashCommandSymbols
