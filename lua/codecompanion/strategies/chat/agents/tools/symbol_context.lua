local log = require("codecompanion.utils.log")

-- Code Extractor helper
local SymbolContext = {}
SymbolContext.__index = SymbolContext

function SymbolContext:new()
  local instance = setmetatable({}, SymbolContext)
  return instance
end

SymbolContext.LSP_TIMEOUT_MS = 10000
SymbolContext.symbol_data = {}
SymbolContext.filetype = ""

SymbolContext.LSP_METHODS = {
  get_definition = vim.lsp.protocol.Methods.textDocument_definition,
  get_references = vim.lsp.protocol.Methods.textDocument_references,
  get_implementation = vim.lsp.protocol.Methods.textDocument_implementation,
}

SymbolContext.TREESITTER_NODES = {
  -- Functions and Classes
  function_definition = true,
  method_definition = true,
  class_definition = true,
  function_declaration = true,
  method_declaration = true,
  constructor_declaration = true,
  class_declaration = true,
  -- Variables and Constants
  variable_declaration = true,
  const_declaration = true,
  let_declaration = true,
  field_declaration = true,
  property_declaration = true,
  const_item = true,
  -- Language-specific definitions
  struct_item = true,
  function_item = true,
  impl_item = true,
  enum_item = true,
  type_item = true,
  attribute_item = true,
  trait_item = true,
  static_item = true,
  interface_declaration = true,
  type_declaration = true,
  decorated_definition = true,
}

function SymbolContext:is_valid_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

function SymbolContext:get_buffer_lines(bufnr, start_row, end_row)
  return vim.api.nvim_buf_get_lines(bufnr, start_row, end_row, false)
end

function SymbolContext:get_node_data(bufnr, node)
  local start_row, start_col, end_row, end_col = node:range()

  local lines = self:get_buffer_lines(bufnr, start_row, end_row + 1)
  if not lines or #lines == 0 then
    return { status = "error", data = "Symbol text range is empty. Tool could not extract symbol data." }
  end

  local code_block
  if start_row == end_row then
    code_block = lines[1]:sub(start_col + 1, end_col)
  else
    lines[1] = lines[1]:sub(start_col + 1)
    lines[#lines] = lines[#lines]:sub(1, end_col)
    code_block = table.concat(lines, "\n")
  end

  local filename = vim.api.nvim_buf_get_name(bufnr)

  return {
    status = "success",
    data = {
      code_block = code_block,
      start_line = start_row + 1,
      end_line = end_row,
      filename = filename,
    },
  }
end

function SymbolContext:get_symbol_data(bufnr, row, col)
  if not self:is_valid_buffer(bufnr) then
    return {
      status = "error",
      data = "Invalid buffer id: " .. bufnr .. ". Internal tool error. Skip future tool calls.",
    }
  end

  local parser = vim.treesitter.get_parser(bufnr)
  if not parser then
    return {
      status = "error",
      data = "Can't initialize tree-sitter parser for buffer id: "
        .. bufnr
        .. ". Internal tool error. Skip future tool calls.",
    }
  end

  local tree = parser:parse()[1]
  local root = tree:root()
  local node = root:named_descendant_for_range(row, col, row, col)

  while node do
    if self.TREESITTER_NODES[node:type()] then
      return self:get_node_data(bufnr, node)
    end
    node = node:parent()
  end

  return {
    status = "error",
    data = "No definition node found at position. Might be unsupported treesitter node type. Skip repeat of this tool calls.",
  }
end

function SymbolContext:validate_lsp_params(bufnr, method)
  if not (bufnr and method) then
    return {
      status = "error",
      data = "Missing bufnr or method. buffer="
        .. bufnr
        .. " method="
        .. method
        .. ". Tool could not find provided symbol in the code. Check spelling.",
    }
  end
  return { status = "success", data = "" }
end

function SymbolContext:execute_lsp_request(bufnr, method)
  local clients = vim.lsp.get_clients({
    bufnr = vim._resolve_bufnr(bufnr),
    method = method,
  })

  if #clients == 0 then
    return {
      status = "error",
      data = "No matching language servers with "
        .. method
        .. " capability. Internal tool error. Skip future tool calls.",
    }
  end

  local lsp_results = {}
  local errors = {}

  for _, client in ipairs(clients) do
    local position_params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    local lsp_result, err = client:request_sync(method, position_params, self.LSP_TIMEOUT_MS, bufnr)
    if err then
      table.insert(errors, "LSP error: " .. tostring(err))
    elseif lsp_result and lsp_result.result then
      if not lsp_results[client.name] then
        lsp_results[client.name] = {}
      end
      lsp_results[client.name] = lsp_result.result
    else
      table.insert(errors, "No results for method: " .. method .. " for client: " .. client.name)
    end
  end

  if next(lsp_results) == nil and #errors > 0 then
    return { status = "error", data = table.concat(errors, "; ") .. ". Internal tool error. Skip future tool calls." }
  end

  return { status = "success", data = lsp_results }
end

function SymbolContext:process_single_range(uri, range)
  if not (uri and range) then
    return { status = "error", data = "Missing uri or range. Internal tool error. Skip future tool calls." }
  end

  local target_bufnr = vim.uri_to_bufnr(uri)
  vim.fn.bufload(target_bufnr)

  local symbol_result = self:get_symbol_data(target_bufnr, range.start.line, range.start.character)
  if symbol_result.status == "success" then
    table.insert(self.symbol_data, symbol_result.data)
    return { status = "success", data = "Symbol processed" }
  else
    return { status = "error", data = "Can't extract symbol data: " .. symbol_result.data }
  end
end

function SymbolContext:process_lsp_result(result)
  if result.range then
    return self:process_single_range(result.uri or result.targetUri, result.range)
  end

  if #result > 20 then
    return { status = "error", data = "Too many results for symbol operation. Ignoring." }
  end

  local errors = {}
  for _, item in pairs(result) do
    local process_result =
      self:process_single_range(item.uri or item.targetUri, item.range or item.targetSelectionRange)
    if process_result.status == "error" then
      table.insert(errors, process_result.data)
    end
  end

  if #errors > 0 then
    return { status = "error", data = table.concat(errors, "; ") }
  end

  return { status = "success", data = "Results processed" }
end

function SymbolContext:call_lsp_method(bufnr, method)
  local validation = self:validate_lsp_params(bufnr, method)
  if validation.status == "error" then
    return { status = "error", data = validation.data }
  end

  local results = self:execute_lsp_request(bufnr, method)
  if results.status == "error" then
    return { status = "error", data = results.data }
  end

  local processed_result = self:process_all_lsp_results(results.data, method)
  if processed_result.status == "success" then
    return { status = "success", data = "Tool executed successfully" }
  else
    return { status = "error", data = processed_result.data }
  end
end

function SymbolContext:process_all_lsp_results(results_by_client, method)
  local processed_count = 0
  local errors = {}

  for client_name, lsp_results in pairs(results_by_client) do
    local process_result = self:process_lsp_result(lsp_results or {})
    if process_result.status == "success" then
      processed_count = processed_count + 1
    else
      table.insert(errors, "Client " .. client_name .. ": " .. process_result.data)
    end
  end

  if #errors > 0 then
    return { status = "error", data = table.concat(errors, "; ") }
  end

  return { status = "success", data = processed_count }
end

function SymbolContext:find_symbol_in_line(line, symbol)
  local pattern = "%f[%w_]" .. vim.pesc(symbol) .. "%f[^%w_]"
  local start_col = line:find(pattern)
  return start_col
end

function SymbolContext:is_searchable_buffer(bufnr)
  return self:is_valid_buffer(bufnr)
    and vim.api.nvim_buf_is_loaded(bufnr)
    and vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
end

function SymbolContext:search_symbol_in_buffer(bufnr, symbol)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  for line_num, line_content in ipairs(lines) do
    local col = self:find_symbol_in_line(line_content, symbol)
    if col then
      return { line = line_num, col = col - 1 }
    end
  end

  return nil
end

function SymbolContext:set_cursor_position(bufnr, position)
  local window_ids = vim.fn.win_findbuf(bufnr)
  if #window_ids == 0 then
    return false
  end

  vim.api.nvim_set_current_win(window_ids[1])
  vim.api.nvim_win_set_cursor(0, { position.line, position.col })
  return true
end

function SymbolContext:move_cursor_to_symbol(symbol)
  if not symbol or symbol == "" then
    return { status = "error", data = "Symbol parameter is required and cannot be empty. Provide a symbol to look for." }
  end

  local buffer_list = vim.api.nvim_list_bufs()

  for _, bufnr in ipairs(buffer_list) do
    if self:is_searchable_buffer(bufnr) then
      local symbol_position = self:search_symbol_in_buffer(bufnr, symbol)

      if symbol_position then
        local cursor_set = self:set_cursor_position(bufnr, symbol_position)
        if cursor_set then
          return { status = "success", data = bufnr }
        end
      end
    end
  end

  return { status = "error", data = "Symbol not found in any loaded buffer. Double check the spelling of the symbol." }
end

-- Helpers initialization
local symbol_context_tool = SymbolContext:new()

---@class CodeCompanion.Tool.SymbolContentTool: CodeCompanion.Agent.Tool
return {
  name = "symbol_context",
  cmds = {
    ---Execute the search commands
    ---@param self CodeCompanion.Tool.GrepSearch
    ---@param args table The arguments from the LLM's tool call
    ---@param input? any The output from the previous function call
    ---@return { status: "success"|"error", data: string|table }
    function(self, args, input)
      local operation = args.operation
      local symbol = args.symbol

      local cursor_result = symbol_context_tool:move_cursor_to_symbol(symbol)

      if cursor_result.status == "error" then
        return cursor_result
      end

      local bufnr = tonumber(cursor_result.data)

      if not symbol_context_tool.LSP_METHODS[operation] then
        return {
          status = "error",
          data = "Unsupported LSP method: " .. operation .. ". Use one of supported lsp methods are: " .. table.concat(
            symbol_context_tool.LSP_METHODS,
            ", "
          ),
        }
      end

      local result = symbol_context_tool:call_lsp_method(bufnr, symbol_context_tool.LSP_METHODS[operation])
      if result.status == "success" then
        symbol_context_tool.filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
        return { status = "success", data = "Tool executed successfully" }
      else
        return { status = "error", data = result.data }
      end
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "symbol_context",
      description = [[Use available LSP operations to build context around unknown code symbols to provide error-proof solution without unnecessary guessing.

== MANDATORY USAGE ==
Use this tool AT THE START of a coding task to gather context about code symbols that are unknown to you and are important to solve the given problem before providing the final answer. This tool should help you solve the problem without any guesses or assumptions.

== Important ==
- Wait for tool results before providing solutions
- Minimize explanations about the tool itself
- When looking for a symbol, pass only the exact name of the symbol without the object. E.g. use: `saveUsers` instead of `userRepository.saveUsers`
]],
      parameters = {
        type = "object",
        properties = {
          operation = {
            type = "string",
            enum = {
              "get_definition",
              "get_references",
              "get_implementation",
            },
            description = "Available LSP operation to be performed by the Symbol Context tool on the given code symbol.",
          },
          symbol = {
            type = "string",
            description = "The unknown code symbol that the Symbol Context tool will use to perform LSP operations.",
          },
        },
        required = {
          "operation",
        },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  handlers = {
    ---@param agent CodeCompanion.Agent The tool object
    ---@return nil
    on_exit = function(_, agent)
      log:trace("[Symbol Content Tool] on_exit handler executed")
      symbol_context_tool.symbol_data = {}
      symbol_context_tool.filetype = ""
      return agent.chat:submit()
    end,
  },
  output = {
    ---@param self CodeCompanion.Tool.GrepSearch
    ---@param agent CodeCompanion.Agent
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, agent, cmd, stdout)
      local operation = self.args.operation
      local symbol = self.args.symbol
      local chat_message_content = ""

      for _, code_block in ipairs(symbol_context_tool.symbol_data) do
        chat_message_content = chat_message_content
          .. string.format(
            [[
---
The %s of symbol: `%s`
Filename: %s
Start line: %s
End line: %s
Content:
```%s
%s
```
]],
            string.upper(operation),
            symbol,
            code_block.filename,
            code_block.start_line,
            code_block.end_line,
            symbol_context_tool.filetype,
            code_block.code_block
          )
      end

      return agent.chat:add_tool_output(self, chat_message_content, chat_message_content)
    end,

    ---@param self CodeCompanion.Tool.GrepSearch
    ---@param agent CodeCompanion.Agent
    ---@param cmd table
    ---@param stderr table The error output from the command
    ---@param stdout? table The output from the command
    error = function(self, agent, cmd, stderr, stdout)
      return agent.chat:add_tool_output(self, tostring(stderr[1]), tostring(stderr[1]))
    end,
  },
}
