local log = require("codecompanion.utils.log")

--- Validates if a buffer is valid and exists
--- @param bufnr number Buffer number to validate
--- @return boolean valid True if buffer is valid, false otherwise
local function is_valid_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

---@class SymbolFinder
local SymbolFinder = {}
SymbolFinder.__index = SymbolFinder

function SymbolFinder:new()
  local instance = setmetatable({}, SymbolFinder)
  return instance
end

--- Finds a symbol within a line of text using word boundary matching
--- @param line string Line of text to search in
--- @param symbol string Symbol to find
--- @return number|nil start_col Starting column of the symbol (1-indexed) or nil if not found
function SymbolFinder:find_symbol_in_line(line, symbol)
  local pattern = "%f[%w_]" .. vim.pesc(symbol) .. "%f[^%w_]"
  local start_col = line:find(pattern)
  return start_col
end

--- Checks if a buffer is searchable (valid, loaded, and modifiable)
--- @param bufnr number Buffer number to check
--- @return boolean searchable True if buffer can be searched, false otherwise
function SymbolFinder:is_searchable_buffer(bufnr)
  return bufnr
    and vim.api.nvim_buf_is_valid(bufnr)
    and vim.api.nvim_buf_is_loaded(bufnr)
    and vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
end

--- Searches for a symbol within all lines of a buffer
--- @param bufnr number Buffer number to search in
--- @param symbol string Symbol to find
--- @return table|nil position Table with line and col fields (1-indexed line, 0-indexed col) or nil if not found
function SymbolFinder:search_symbol_in_buffer(bufnr, symbol)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  for line_num, line_content in ipairs(lines) do
    local col = self:find_symbol_in_line(line_content, symbol)
    if col then
      return { line = line_num, col = col }
    end
  end

  return nil
end

--- Sets cursor position in a window displaying the specified buffer
--- @param bufnr number Buffer number to set cursor in
--- @param position table Position with line and col fields
--- @return boolean success True if cursor was set successfully, false otherwise
function SymbolFinder:set_cursor_position(bufnr, position)
  local window_ids = vim.fn.win_findbuf(bufnr)
  if #window_ids == 0 then
    return false
  end

  vim.api.nvim_set_current_win(window_ids[1])
  vim.api.nvim_win_set_cursor(0, { position.line, position.col })
  return true
end

--- Moves cursor to the first occurrence of a symbol across all loaded buffers
--- @param symbol string Symbol to search for and move cursor to
--- @return table result Contains status and data with buffer number or error message
function SymbolFinder:move_cursor_to_symbol(symbol)
  if not symbol or symbol == "" then
    return { status = "error", data = "Symbol parameter is required and cannot be empty. Provide a symbol to look for." }
  end

  local buffer_list = vim.api.nvim_list_bufs()

  vim.cmd("stopinsert")

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

local symbol_finder = SymbolFinder:new()

---@class CodeExtractor
local CodeExtractor = {}
CodeExtractor.__index = CodeExtractor

function CodeExtractor:new()
  local instance = setmetatable({}, CodeExtractor)
  return instance
end

CodeExtractor.TREESITTER_NODES = {
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

--- Extracts code block data from a treesitter node
--- @param bufnr number Buffer number containing the node
--- @param node table Treesitter node to extract data from
--- @return table result Contains status and data with code_block, start_line, end_line, filename
function CodeExtractor:get_node_data(bufnr, node)
  local start_row, start_col, end_row, end_col = node:range()

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
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

--- Gets symbol data at a specific position using treesitter
--- @param bufnr number Buffer number to analyze
--- @param row number Row position (0-indexed)
--- @param col number Column position (0-indexed)
--- @return table result Contains status and data with symbol information or error message
function CodeExtractor:get_symbol_data(bufnr, row, col)
  if not is_valid_buffer(bufnr) then
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

local code_extractor = CodeExtractor:new()

---@class OperationExecutor
local OperationExecutor = {}
OperationExecutor.__index = OperationExecutor

-- Constants for LSP methods and Tree-sitter nodes
OperationExecutor.LSP_METHODS = {
  get_definition = vim.lsp.protocol.Methods.textDocument_definition,
  get_references = vim.lsp.protocol.Methods.textDocument_references,
  get_implementation = vim.lsp.protocol.Methods.textDocument_implementation,
}

OperationExecutor.LSP_TIMEOUT_MS = 10000

--- Creates a new instance of SymbolContextTool
--- @return OperationExecutor instance New SymbolContextTool instance
function OperationExecutor:new()
  local instance = setmetatable({}, OperationExecutor)
  return instance
end

--- Stores symbol data and filetype information
OperationExecutor.symbol_data = {}
OperationExecutor.filetype = ""

--- Validates LSP request parameters
--- @param bufnr number Buffer number for the request
--- @param method string LSP method name
--- @return table result Contains status and data indicating validation result
function OperationExecutor:validate_lsp_params(bufnr, method)
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

--- Executes an LSP request synchronously across all applicable clients
--- @param bufnr number Buffer number for the LSP request
--- @param method string LSP method to execute
--- @return table result Contains status and data with LSP results by client or error message
function OperationExecutor:execute_lsp_request(bufnr, method)
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
    ---@diagnostic disable-next-line: inject-field
    position_params.context = {
      includeDeclaration = false,
    }
    local lsp_result, err = client:request_sync(method, position_params, self.LSP_TIMEOUT_MS)
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

--- Processes a single range from LSP results and extracts symbol data
--- @param uri string URI of the file containing the range
--- @param range table LSP range object with start and end positions
--- @return table result Contains status and data indicating processing result
function OperationExecutor:process_single_range(uri, range)
  if not (uri and range) then
    return { status = "error", data = "Missing uri or range. Internal tool error. Skip future tool calls." }
  end

  local target_bufnr = vim.uri_to_bufnr(uri)
  vim.fn.bufload(target_bufnr)

  local symbol_result = code_extractor:get_symbol_data(target_bufnr, range.start.line, range.start.character)
  if symbol_result.status == "success" then
    table.insert(self.symbol_data, symbol_result.data)
    return { status = "success", data = "Symbol processed" }
  else
    return { status = "error", data = "Can't extract symbol data: " .. symbol_result.data }
  end
end

--- Processes LSP results, handling both single items and arrays
--- @param result table LSP result data, either single item or array
--- @return table result Contains status and data indicating processing result
function OperationExecutor:process_lsp_result(result)
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

--- Main method to execute LSP operations and process results
--- @param bufnr number Buffer number for the LSP request
--- @param method string LSP method to execute
--- @return table result Contains status and data indicating overall operation result
function OperationExecutor:call_lsp_method(bufnr, method)
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

--- Processes LSP results from all clients that responded
--- @param results_by_client table LSP results organized by client name
--- @param method string LSP method that was executed
--- @return table result Contains status and data with processing count or error messages
function OperationExecutor:process_all_lsp_results(results_by_client, method)
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

local lsp_code_extractor = OperationExecutor:new()

---@class CodeCompanion.Tool.SymbolContext: CodeCompanion.Agent.Tool
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

      local cursor_result = symbol_finder:move_cursor_to_symbol(symbol)

      if cursor_result.status == "error" then
        return cursor_result
      end

      local bufnr = tonumber(cursor_result.data)

      if not lsp_code_extractor.LSP_METHODS[operation] then
        return {
          status = "error",
          data = "Unsupported LSP method: " .. operation .. ". Use one of supported lsp methods: " .. table.concat(
            lsp_code_extractor.LSP_METHODS,
            ", "
          ),
        }
      end

      ---@diagnostic disable-next-line: param-type-mismatch
      local result = lsp_code_extractor:call_lsp_method(bufnr, lsp_code_extractor.LSP_METHODS[operation])
      if result.status == "success" then
        lsp_code_extractor.filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
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
            description = "The unknown code symbol that the Symbol Context tool will use as argument for LSP operations.",
          },
        },
        required = {
          "operation",
          "symbol",
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
      lsp_code_extractor.symbol_data = {}
      lsp_code_extractor.filetype = ""
      return agent.chat:submit()
    end,
  },
  output = {
    ---@param self CodeCompanion.Tool.SymbolContext
    ---@param agent CodeCompanion.Agent
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, agent, cmd, stdout)
      local operation = self.args.operation
      local symbol = self.args.symbol
      local chat_message_content = ""

      for _, code_block in ipairs(lsp_code_extractor.symbol_data) do
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
            lsp_code_extractor.filetype,
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
