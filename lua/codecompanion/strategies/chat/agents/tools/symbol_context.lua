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

--- Gets file pattern for ripgrep based on filetype
--- @param filetype string File extension or type (e.g., "lua", "javascript", "java")
--- @return string pattern Ripgrep file pattern
function SymbolFinder:get_filetype_pattern(filetype)
  if not filetype or filetype == "" then
    return ""
  end

  return string.format("--type %s", filetype)
end

--- Searches for a symbol in the workspace using grep (ripgrep) and quickfix list
--- @param symbol string Symbol to search for
--- @param filetype string|nil File type to search in (optional)
--- @return table|nil result Table with file, line, col, and text or nil if not found
function SymbolFinder:search_symbol_in_workspace(symbol, filetype)
  local search_pattern = "\\b" .. vim.fn.escape(symbol, "\\") .. "\\b"

  -- Build the grep command
  local cmd = string.format(
    "silent! grep! %s %s",
    filetype and self:get_filetype_pattern(filetype) or "",
    vim.fn.shellescape(search_pattern)
  )

  ---@diagnostic disable-next-line: param-type-mismatch
  local success, _ = pcall(vim.cmd, cmd)

  if not success then
    return nil
  end

  -- Get the quickfix list
  local qflist = vim.fn.getqflist()

  if #qflist == 0 then
    return nil
  end

  -- Return the first match
  local first_match = qflist[1]
  return {
    file = vim.fn.bufname(first_match.bufnr),
    line = first_match.lnum,
    col = first_match.col - 1, -- Convert to 0-indexed
    text = first_match.text,
    bufnr = first_match.bufnr,
  }
end

--- Opens a file and sets cursor position
--- @param filepath string Path to the file
--- @param line number Line number (1-indexed)
--- @param col number Column number (0-indexed)
--- @return boolean success True if file was opened and cursor set successfully
function SymbolFinder:open_file_and_set_cursor(filepath, line, col)
  -- Open the file
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))

  -- Set cursor position
  vim.api.nvim_win_set_cursor(0, { line, col })

  -- Center the line on screen
  vim.cmd("normal! zz")

  return true
end

--- Moves cursor to the first occurrence of a symbol in the workspace
--- @param symbol string Symbol to search for and move cursor to
--- @param filetype string|nil File type to search in (e.g., "lua", "javascript", "java")
--- @return table result Contains status and data with file info or error message
function SymbolFinder:move_cursor_to_symbol(symbol, filetype)
  if not symbol or symbol == "" then
    return { status = "error", data = "Symbol parameter is required and cannot be empty. Provide a symbol to look for." }
  end

  vim.cmd("stopinsert")

  local match = self:search_symbol_in_workspace(symbol, filetype)

  if not match then
    local filetype_msg = filetype and (" in " .. filetype .. " files") or ""
    return {
      status = "error",
      data = "Symbol not found in workspace" .. filetype_msg .. ". Double check the spelling of the symbol.",
    }
  end

  -- Open file and position cursor
  local success = self:open_file_and_set_cursor(match.file, match.line, match.col)

  if success then
    return {
      status = "success",
      data = {
        file = match.file,
        line = match.line,
        col = match.col,
        bufnr = match.bufnr,
      },
    }
  else
    return { status = "error", data = "Failed to open file or set cursor position." }
  end
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

---@class LSPCaller
local LSPCaller = {}
LSPCaller.__index = LSPCaller

-- Constants for LSP methods and Tree-sitter nodes
LSPCaller.LSP_METHODS = {
  get_definition = vim.lsp.protocol.Methods.textDocument_definition,
  get_references = vim.lsp.protocol.Methods.textDocument_references,
  get_implementation = vim.lsp.protocol.Methods.textDocument_implementation,
}

LSPCaller.LSP_TIMEOUT_MS = 10000

--- Creates a new instance of SymbolContextTool
--- @return LSPCaller instance New SymbolContextTool instance
function LSPCaller:new()
  local instance = setmetatable({}, LSPCaller)
  return instance
end

--- Stores symbol data and filetype information
LSPCaller.symbol_data = {}
LSPCaller.filetype = ""

--- Validates LSP request parameters
--- @param bufnr number Buffer number for the request
--- @param method string LSP method name
--- @return table result Contains status and data indicating validation result
function LSPCaller:validate_lsp_params(bufnr, method)
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
function LSPCaller:execute_lsp_request(bufnr, method)
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
function LSPCaller:process_single_range(uri, range)
  if not (uri and range) then
    return { status = "error", data = "Missing uri or range. Internal tool error. Skip future tool calls." }
  end

  local target_bufnr = vim.uri_to_bufnr(uri)
  vim.fn.bufload(target_bufnr)

  local symbol_result = code_extractor:get_symbol_data(target_bufnr, range.start.line, range.start.character)
  if symbol_result.status == "success" then
    -- Check if element with same filename, start_line and end_line already exists
    local duplicate_exists = false
    for _, existing_data in ipairs(self.symbol_data) do
      if
        existing_data.filename == symbol_result.data.filename
        and existing_data.start_line == symbol_result.data.start_line
        and existing_data.end_line == symbol_result.data.end_line
      then
        duplicate_exists = true
        break
      end
    end

    -- Only insert if no duplicate exists
    if not duplicate_exists then
      table.insert(self.symbol_data, symbol_result.data)
    end

    return { status = "success", data = "Symbol processed" }
  else
    return { status = "error", data = "Can't extract symbol data: " .. symbol_result.data }
  end
end

--- Processes LSP results, handling both single items and arrays
--- @param result table LSP result data, either single item or array
--- @return table result Contains status and data indicating processing result
function LSPCaller:process_lsp_result(result)
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
function LSPCaller:call_lsp_method(bufnr, method)
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
function LSPCaller:process_all_lsp_results(results_by_client, method)
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

local lsp_caller = LSPCaller:new()

---@class CodeCompanion.Tool.SymbolContext: CodeCompanion.Agent.Tool
return {
  name = "symbol_context",
  cmds = {
    ---Execute the search commands
    ---@param self CodeCompanion.Tool.SymbolContext
    ---@param args table The arguments from the LLM's tool call
    ---@param input? any The output from the previous function call
    ---@return { status: "success"|"error", data: string|table }
    function(self, args, input)
      local operation = args.operation
      local symbol = args.symbol

      ---@diagnostic disable-next-line: undefined-field
      local context_filetype = self.chat.context.filetype
      ---@diagnostic disable-next-line: undefined-field
      local context_winnr = self.chat.context.winnr

      local chat_winnr = vim.api.nvim_get_current_win()

      vim.api.nvim_set_current_win(context_winnr)

      if not lsp_caller.LSP_METHODS[operation] then
        return {
          status = "error",
          data = "Unsupported LSP method: " .. operation .. ". Use one of supported lsp methods: " .. table.concat(
            lsp_caller.LSP_METHODS,
            ", "
          ),
        }
      end

      local cursor_result = symbol_finder:move_cursor_to_symbol(symbol, context_filetype)

      if cursor_result.status == "error" then
        return cursor_result
      end

      local bufnr = tonumber(cursor_result.data.bufnr)

      ---@diagnostic disable-next-line: param-type-mismatch
      local result = lsp_caller:call_lsp_method(bufnr, lsp_caller.LSP_METHODS[operation])
      vim.api.nvim_set_current_win(chat_winnr)
      if result.status == "success" then
        lsp_caller.filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
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
      lsp_caller.symbol_data = {}
      lsp_caller.filetype = ""
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
      local chat_message_content = string.format("The %s of symbol: `%s`\n", string.upper(operation), symbol)

      for _, code_block in ipairs(lsp_caller.symbol_data) do
        chat_message_content = chat_message_content
          .. string.format(
            [[
---
Filename: %s
Start line: %s
End line: %s
Content:
```%s
%s
```
]],
            code_block.filename,
            code_block.start_line,
            code_block.end_line,
            lsp_caller.filetype,
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
