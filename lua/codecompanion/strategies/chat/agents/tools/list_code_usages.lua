local log = require("codecompanion.utils.log")

---@class SymbolFinder
local SymbolFinder = {}
SymbolFinder.__index = SymbolFinder

function SymbolFinder:new()
  return setmetatable({}, SymbolFinder)
end

--- Searches for a symbol in the workspace using grep (ripgrep) and quickfix list
--- @param symbolName string Symbol to search for
--- @param filetype? string|nil File type to search in (optional)
--- @param filepaths? table|nil List of file paths to search in (optional)
--- @return table|nil result Table with file, line, col, and text or nil if not found
function SymbolFinder:grep_symbol_in_workspace(symbolName, filetype, filepaths)
  local search_pattern = "\\b" .. vim.fn.escape(symbolName, "\\") .. "\\b"
  local cmd = "silent! grep! "

  -- Add filetype pattern if provided
  if filetype and filetype ~= "" then
    cmd = cmd .. string.format("--type %s", filetype) .. " "
  end

  -- Add search pattern
  cmd = cmd .. vim.fn.shellescape(search_pattern)

  -- Add specific filepaths if provided
  if filepaths and type(filepaths) == "table" and #filepaths > 0 then
    cmd = cmd .. " " .. table.concat(filepaths, " ")
  end

  log:debug("[SymbolFinder] Executing grep command: %s", cmd)

  ---@diagnostic disable-next-line: param-type-mismatch
  local success, _ = pcall(vim.cmd, cmd)
  if not success then
    return nil
  end

  local qflist = vim.fn.getqflist()
  log:debug("[SymbolFinder] Quickfix list after grep: %s", vim.inspect(qflist))
  if #qflist == 0 then
    return nil
  end

  local first_match = qflist[1]
  return {
    file = vim.fn.bufname(first_match.bufnr),
    line = first_match.lnum,
    col = first_match.col,
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
  log:debug("[SymbolFinder] Opening file: %s at line: %d, col: %d", filepath, line, col)
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  vim.api.nvim_win_set_cursor(0, { line, col })
  vim.cmd("normal! zz")
  return true
end

--- Moves cursor to the first occurrence of a symbol in the workspace
--- @param symbolName string Symbol to search for and move cursor to
--- @param filetype? string|nil File type to search in (e.g., "lua", "javascript", "java")
--- @param filepaths? table|nil List of file paths to search in (optional)
--- @return table result Contains status and data with file info or error message
function SymbolFinder:move_cursor_to_symbol(symbolName, filetype, filepaths)
  if not symbolName or symbolName == "" then
    return { status = "error", data = "Symbol parameter is required and cannot be empty." }
  end

  vim.cmd("stopinsert")

  local match = self:grep_symbol_in_workspace(symbolName, filetype, filepaths)
  if not match then
    local filetype_msg = filetype and (" in " .. filetype .. " files") or ""
    return {
      status = "error",
      data = "Symbol not found in workspace" .. filetype_msg .. ". Double check the spelling of the symbol.",
    }
  end

  local success = self:open_file_and_set_cursor(match.file, match.line, match.col)

  if success then
    return {
      status = "success",
      data = {
        bufnr = match.bufnr,
      },
    }
  else
    return { status = "error", data = "Failed to open file or set cursor position." }
  end
end

local symbol_finder = SymbolFinder:new()

---@class CodeExtractor
--- Extracts code blocks using treesitter
local CodeExtractor = {}
CodeExtractor.__index = CodeExtractor

function CodeExtractor:new()
  return setmetatable({}, CodeExtractor)
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
  use_declaration = true,
  import_declaration = true,
}

--- Extracts code block data from a treesitter node
--- @param bufnr number Buffer number containing the node
--- @param node table Treesitter node to extract data from
--- @return table result Contains status and data with code_block, start_line, end_line, filename
function CodeExtractor:get_node_data(bufnr, node)
  local start_row, start_col, end_row, end_col = node:range()
  log:debug(
    "[CodeExtractor] Extracting node data from buffer %d, range: (%d, %d) to (%d, %d)",
    bufnr,
    start_row,
    start_col,
    end_row,
    end_col
  )

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
  log:debug("[CodeExtractor] Extracted lines from buffer %d: %s", bufnr, vim.inspect(lines))
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
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return {
      status = "error",
      data = "Invalid buffer id: " .. bufnr .. ". Internal tool error.",
    }
  end

  local parser = vim.treesitter.get_parser(bufnr)
  if not parser then
    return {
      status = "error",
      data = "Can't initialize tree-sitter parser for buffer id: "
        .. bufnr
        .. ". Internal tool error. Missing treesitter package?.",
    }
  end

  local tree = parser:parse()[1]
  local root = tree:root()
  local node = root:named_descendant_for_range(row, col, row, col)

  while node do
    log:debug("[CodeExtractor] Checking node type '%s' at position (%d, %d) in buffer %d", node:type(), row, col, bufnr)
    if self.TREESITTER_NODES[node:type()] then
      return self:get_node_data(bufnr, node)
    end
    node = node:parent()
  end

  return {
    status = "error",
    data = "No definition node found at position. Might be unsupported treesitter node type. Internal tool error.",
  }
end

local code_extractor = CodeExtractor:new()

---@class LSPCaller
local LSPCaller = {}
LSPCaller.__index = LSPCaller

-- Constants for LSP methods and Tree-sitter nodes
LSPCaller.LSP_METHODS = {
  definition = vim.lsp.protocol.Methods.textDocument_definition,
  references = vim.lsp.protocol.Methods.textDocument_references,
  implementations = vim.lsp.protocol.Methods.textDocument_implementation,
  declaration = vim.lsp.protocol.Methods.textDocument_declaration,
  type_definition = vim.lsp.protocol.Methods.textDocument_typeDefinition,
  documentation = vim.lsp.protocol.Methods.textDocument_hover,
}

LSPCaller.LSP_TIMEOUT_MS = 60000
LSPCaller.symbol_data = {}
LSPCaller.filetype = ""

--- Creates a new instance of ListCodeUsagesTool
--- @return LSPCaller instance New ListCodeUsagesTool instance
function LSPCaller:new()
  return setmetatable({}, LSPCaller)
end

function LSPCaller:filter_project_references(references)
  local project_root = vim.fn.getcwd()

  local filtered_results = {}
  for _, reference in ipairs(references) do
    local uri = reference.uri
    if uri then
      local filepath = uri:gsub("file://", "")
      if filepath:find(project_root, 1, true) == 1 then
        table.insert(filtered_results, reference)
      end
    end
  end

  log:debug(
    "[LSPCaller] LSP references filtered for project. Original: %d, Filtered: %d",
    #references,
    #filtered_results
  )

  return filtered_results
end

-- Then modify the execute_lsp_request function to use this new function
function LSPCaller:execute_lsp_request(bufnr, method)
  local clients = vim.lsp.get_clients({
    method = method,
  })
  log:debug(
    "[LSPCaller] Executing LSP method '%s' on buffer %d with clients: %s",
    method,
    bufnr,
    vim.inspect(vim.tbl_map(function(client)
      return client.name
    end, clients))
  )

  local lsp_results = {}
  local errors = {}

  for _, client in ipairs(clients) do
    if not vim.lsp.buf_is_attached(bufnr, client.id) then
      log:debug("[LSPCaller] Attaching client '%s' to buffer %d", client.name, bufnr)
      vim.lsp.buf_attach_client(bufnr, client.id)
    end
    local position_params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    ---@diagnostic disable-next-line: inject-field
    position_params.context = { includeDeclaration = false } -- some LSPs require this context for references

    local lsp_result, err = client:request_sync(method, position_params, self.LSP_TIMEOUT_MS)

    if method == self.LSP_METHODS.documentation and lsp_result and lsp_result.result and lsp_result.result.contents then
      lsp_result.result = {
        range = lsp_result.result.range,
        contents = lsp_result.result.contents.value or lsp_result.result.contents,
      }
    end

    if err then
      table.insert(errors, "LSP error: " .. tostring(err))
      log:debug("[LSPCaller] LSP request '%s' failed for client '%s': %s", method, client.name, tostring(err))
    elseif lsp_result and lsp_result.result then
      if not lsp_results[client.name] then
        lsp_results[client.name] = {}
      end

      -- If this is a references request, filter the results
      if method == self.LSP_METHODS.references and type(lsp_result.result) == "table" then
        lsp_results[client.name] = self:filter_project_references(lsp_result.result)
      else
        lsp_results[client.name] = lsp_result.result
      end

      log:debug(
        "[LSPCaller] LSP request '%s' succeeded for client '%s': %s",
        method,
        client.name,
        vim.inspect(lsp_result.result)
      )
    end
  end

  return { status = "success", data = lsp_results }
end

--- Processes a single range from LSP results and extracts symbol data
--- @param uri string URI of the file containing the range
--- @param range table LSP range object with start and end positions
--- @return table result Contains status and data indicating processing result
function LSPCaller:process_single_range(uri, range, operation)
  if not (uri and range) then
    return { status = "error", data = "Missing uri or range. Internal tool error." }
  end

  local target_bufnr = vim.uri_to_bufnr(uri)
  log:debug(
    "[LSPCaller] Processing single range for operation '%s' in buffer %d, range: %s",
    operation,
    target_bufnr,
    vim.inspect(range)
  )
  vim.fn.bufload(target_bufnr)

  local symbol_result = code_extractor:get_symbol_data(target_bufnr, range.start.line, range.start.character)
  log:debug("[LSPCaller] Processed symbol data for operation '%s': %s", operation, vim.inspect(symbol_result))
  if symbol_result.status == "success" then
    -- Check if element with same filename, start_line and end_line already exists
    local duplicate = false
    for _, code_blocks in pairs(self.symbol_data) do
      for _, code_block in ipairs(code_blocks) do
        if
          code_block.filename == symbol_result.data.filename
          and code_block.start_line == symbol_result.data.start_line
          and code_block.end_line == symbol_result.data.end_line
        then
          duplicate = true
          break
        end
      end
    end

    if not duplicate then
      if not self.symbol_data[operation] then
        self.symbol_data[operation] = {}
      end
      table.insert(self.symbol_data[operation], symbol_result.data)
    end

    return { status = "success", data = "Symbol processed" }
  else
    return { status = "error", data = "Can't extract symbol data: " .. symbol_result.data }
  end
end

--- Processes LSP results, handling both single items and arrays
--- @param result table LSP result data, either single item or array
--- @return table result Contains status and data indicating processing result
function LSPCaller:process_lsp_result(result, operation)
  if result.contents then
    if not self.symbol_data[operation] then
      self.symbol_data[operation] = {}
    end

    local content_to_insert = result.contents
    if type(result.contents) == "table" and type(result.contents[#result.contents]) == "string" then
      content_to_insert = result.contents[#result.contents]
    end

    table.insert(self.symbol_data[operation], {
      code_block = content_to_insert,
    })

    return { status = "success", data = "Hover content processed" }
  end

  if result.range then
    return self:process_single_range(result.uri or result.targetUri, result.range, operation)
  end

  local errors = {}
  for _, item in pairs(result) do
    local process_result =
      self:process_single_range(item.uri or item.targetUri, item.range or item.targetSelectionRange, operation)
    if process_result.status == "error" then
      table.insert(errors, process_result.data)
    end
  end

  if #errors > 0 then
    return { status = "error", data = table.concat(errors, "; ") }
  end

  return { status = "success", data = "Results processed" }
end

--- Processes LSP results from all clients that responded
--- @param results_by_client table LSP results organized by client name
--- @param operation string operation that was executed
--- @return table result Contains status and data with processing count or error messages
function LSPCaller:process_all_lsp_results(results_by_client, operation)
  local processed_count = 0
  local errors = {}

  for client_name, lsp_results in pairs(results_by_client) do
    local process_result = self:process_lsp_result(lsp_results or {}, operation)
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

--- Main method to execute LSP operations and process results
--- @param bufnr number Buffer number for the LSP request
--- @param method string LSP method to execute
--- @return table result Contains status and data indicating overall operation result
function LSPCaller:call_lsp_method_and_store_results(bufnr, method, operation)
  if not (bufnr and method and operation) then
    return {
      status = "error",
      data = "Missing bufnr or method or operation.",
    }
  end

  local results = self:execute_lsp_request(bufnr, method)
  if results.status == "error" then
    return results
  end

  return self:process_all_lsp_results(results.data, operation)
end

local lsp_caller = LSPCaller:new()

---@class CodeCompanion.Tool.ListCodeUsages: CodeCompanion.Agent.Tool
return {
  name = "list_code_usages",
  cmds = {
    ---Execute the find usages tool
    ---@param self CodeCompanion.Tool.ListCodeUsages
    ---@param args table The arguments from the LLM's tool call
    ---@param input? any The output from the previous function call
    ---@return { status: "success"|"error", data: string|table }
    function(self, args, input)
      local symbolName = args.symbolName
      local filePaths = args.filePaths

      log:trace(
        "[List Code Usages Tool] Executing with symbolName: %s, filePaths: %s",
        symbolName,
        vim.inspect(filePaths)
      )

      ---@diagnostic disable-next-line: undefined-field
      local context_filetype = self.chat.context.filetype
      ---@diagnostic disable-next-line: undefined-field
      local context_winnr = self.chat.context.winnr
      local chat_winnr = vim.api.nvim_get_current_win()

      vim.api.nvim_set_current_win(context_winnr)

      -- Reset symbol data before new search
      lsp_caller.symbol_data = {}

      local symbol_found = false
      local bufnr
      local cursor_result

      if filePaths and type(filePaths) == "table" and #filePaths > 0 then
        log:debug("[List Code Usages Tool] Searching in specified file paths: %s", vim.inspect(filePaths))
        cursor_result = symbol_finder:move_cursor_to_symbol(symbolName, nil, filePaths)
        if cursor_result and cursor_result.status == "success" then
          symbol_found = true
        end
      end

      if not symbol_found then
        log:debug(
          "[List Code Usages Tool] Searching in workspace for symbol: %s and filetype: %s",
          symbolName,
          context_filetype
        )
        cursor_result = symbol_finder:move_cursor_to_symbol(symbolName, context_filetype, nil)

        if cursor_result.status == "error" then
          vim.api.nvim_set_current_win(chat_winnr)
          return cursor_result
        end
        symbol_found = true
      end

      local results_num = 0

      if symbol_found then
        log:debug("[List Code Usages Tool] Symbol found, processing usages for symbol: %s", symbolName)
        bufnr = tonumber(cursor_result.data.bufnr)
        for operation, method in pairs(lsp_caller.LSP_METHODS) do
          log:debug(
            "[List Code Usages Tool] Calling LSP method '%s' for operation '%s' on buffer %d",
            method,
            operation,
            bufnr
          )
          ---@diagnostic disable-next-line: param-type-mismatch
          local lsp_call_result = lsp_caller:call_lsp_method_and_store_results(bufnr, method, operation)
          if lsp_call_result.status == "success" then
            results_num = results_num + lsp_call_result.data
          else
            return lsp_call_result
          end
        end
      end

      vim.api.nvim_set_current_win(chat_winnr)

      if results_num > 0 then
        lsp_caller.filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
        return { status = "success", data = "Tool executed successfully" }
      else
        return {
          status = "error",
          data = "No usages found for symbol: " .. symbolName,
        }
      end
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "list_code_usages",
      description = [[
Request to list all usages (references, definitions, implementations etc) of a function, class, method, variable etc. Use this tool when
1. Looking for a sample implementation of an interface or class
2. Checking how a function is used throughout the codebase.
3. Including and updating all usages when changing a function, method, or constructor]],
      parameters = {
        type = "object",
        properties = {
          symbolName = {
            type = "string",
            description = "The name of the symbol, such as a function name, class name, method name, variable name, etc.",
          },
          filePaths = {
            type = "array",
            description = "One or more file paths which likely contain the definition of the symbol. For instance the file which declares a class or function. This is optional but will speed up the invocation of this tool and improve the quality of its output.",
            items = {
              type = "string",
            },
          },
        },
        required = {
          "symbolName",
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
      log:trace("[List Code Usages Tool] on_exit handler executed")
      lsp_caller.symbol_data = {}
      lsp_caller.filetype = ""
    end,
  },
  output = {
    ---@param self CodeCompanion.Tool.ListCodeUsages
    ---@param agent CodeCompanion.Agent
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, agent, cmd, stdout)
      local symbol = self.args.symbolName
      local chat_message_content = ""

      for operation, code_blocks in pairs(lsp_caller.symbol_data) do
        chat_message_content = chat_message_content .. string.format("\n%s of symbol: `%s`\n", operation, symbol)
        for _, code_block in ipairs(code_blocks) do
          if operation == "documentation" then
            chat_message_content = chat_message_content
              .. string.format(
                [[
---
%s
]],
                code_block.code_block
              )
          else
            chat_message_content = chat_message_content
              .. string.format(
                [[
---
Filename: %s:%s-%s
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
        end
      end

      return agent.chat:add_tool_output(self, chat_message_content)
    end,

    ---@param self CodeCompanion.Tool.GrepSearch
    ---@param agent CodeCompanion.Agent
    ---@param cmd table
    ---@param stderr table The error output from the command
    ---@param stdout? table The output from the command
    error = function(self, agent, cmd, stderr, stdout)
      return agent.chat:add_tool_output(self, tostring(stderr[1]))
    end,
  },
}
