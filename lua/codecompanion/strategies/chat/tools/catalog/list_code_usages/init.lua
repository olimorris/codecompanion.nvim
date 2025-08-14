local LspHandler = require("codecompanion.strategies.chat.tools.catalog.list_code_usages.lsp_handler")
local ResultProcessor = require("codecompanion.strategies.chat.tools.catalog.list_code_usages.result_processor")
local SymbolFinder = require("codecompanion.strategies.chat.tools.catalog.list_code_usages.symbol_finder")
local Utils = require("codecompanion.strategies.chat.tools.catalog.list_code_usages.utils")

local api = vim.api
local fmt = string.format

---@class CodeCompanion.Tool.ListCodeUsages: CodeCompanion.Tools.Tool
---@field symbol_data table Storage for collected symbol data across different operations
---@field filetype string The detected filetype for syntax highlighting in output
local ListCodeUsagesTool = {}

local CONSTANTS = {
  LSP_METHODS = {
    definition = vim.lsp.protocol.Methods.textDocument_definition,
    references = vim.lsp.protocol.Methods.textDocument_references,
    implementations = vim.lsp.protocol.Methods.textDocument_implementation,
    declaration = vim.lsp.protocol.Methods.textDocument_declaration,
    type_definition = vim.lsp.protocol.Methods.textDocument_typeDefinition,
    documentation = vim.lsp.protocol.Methods.textDocument_hover,
  },
}

--- Asynchronously processes LSP symbols by navigating to each symbol location
--- and executing all LSP methods to gather comprehensive information.
---
--- This function handles the complex async flow of:
--- 1. Opening each symbol's file
--- 2. Setting cursor to symbol position
--- 3. Executing all LSP methods (definition, references, implementations, etc.)
--- 4. Collecting and processing results
---
---@param symbols table[] Array of symbol objects from LSP workspace symbol search
---@param state table Shared state containing symbol_data and filetype
---@param callback function Callback function called with total results count when complete
local function process_lsp_symbols_async(symbols, state, callback)
  local results_count = 0
  local completed_symbols = 0
  local total_symbols = #symbols

  if total_symbols == 0 then
    callback(0)
    return
  end

  for _, symbol in ipairs(symbols) do
    local filepath = symbol.file
    local line = symbol.range.start.line + 1 -- Convert to 1-indexed
    local col = symbol.range.start.character

    Utils.async_edit_file(filepath, function(edit_success)
      if edit_success then
        Utils.async_set_cursor(line, col, function(cursor_success)
          if cursor_success then
            local current_bufnr = api.nvim_get_current_buf()
            local methods_to_process = {}

            -- Collect all methods to process
            for operation, method in pairs(CONSTANTS.LSP_METHODS) do
              table.insert(methods_to_process, { operation = operation, method = method })
            end

            local completed_methods = 0
            local total_methods = #methods_to_process

            -- Process each LSP method
            for _, method_info in ipairs(methods_to_process) do
              LspHandler.execute_request_async(current_bufnr, method_info.method, function(lsp_result)
                results_count = results_count
                  + ResultProcessor.process_lsp_results(lsp_result, method_info.operation, state.symbol_data)

                completed_methods = completed_methods + 1
                if completed_methods == total_methods then
                  -- Save filetype for the output
                  if results_count > 0 and not state.filetype then
                    state.filetype = Utils.safe_get_filetype(current_bufnr)
                  end

                  completed_symbols = completed_symbols + 1
                  if completed_symbols == total_symbols then
                    callback(results_count)
                  end
                end
              end)
            end
          else
            completed_symbols = completed_symbols + 1
            if completed_symbols == total_symbols then
              callback(results_count)
            end
          end
        end)
      else
        completed_symbols = completed_symbols + 1
        if completed_symbols == total_symbols then
          callback(results_count)
        end
      end
    end)
  end
end

--- Asynchronously processes grep search results to gather symbol information.
---
--- When LSP doesn't find all symbol occurrences, this function processes the first
--- grep match and executes LSP methods from that position to gather additional data.
--- It also processes the entire quickfix list for comprehensive coverage.
---
---@param grep_result table|nil Grep result containing file, line, col, and qflist
---@param state table Shared state containing symbol_data and filetype
---@param callback function Callback function called with results count when complete
local function process_grep_results_async(grep_result, state, callback)
  local results_count = 0

  if not grep_result then
    callback(results_count)
    return
  end

  Utils.async_edit_file(grep_result.file, function(edit_success)
    if edit_success then
      Utils.async_set_cursor(grep_result.line, grep_result.col, function(cursor_success)
        if cursor_success then
          local current_bufnr = api.nvim_get_current_buf()
          local methods_to_process = {}

          -- Collect all methods to process
          for operation, method in pairs(CONSTANTS.LSP_METHODS) do
            table.insert(methods_to_process, { operation = operation, method = method })
          end

          local completed_methods = 0
          local total_methods = #methods_to_process

          -- Process each LSP method
          for _, method_info in ipairs(methods_to_process) do
            LspHandler.execute_request_async(current_bufnr, method_info.method, function(lsp_result)
              results_count = results_count
                + ResultProcessor.process_lsp_results(lsp_result, method_info.operation, state.symbol_data)

              completed_methods = completed_methods + 1
              if completed_methods == total_methods then
                -- Process quickfix list results
                if grep_result.qflist then
                  results_count = results_count
                    + ResultProcessor.process_quickfix_references(grep_result.qflist, state.symbol_data)
                end

                -- Save filetype if needed
                if results_count > 0 and not state.filetype then
                  state.filetype = Utils.safe_get_filetype(current_bufnr)
                end

                callback(results_count)
              end
            end)
          end
        else
          callback(results_count)
        end
      end)
    else
      callback(results_count)
    end
  end)
end

--- Extracts file extension from the context buffer to help focus search results.
---
--- This is used to filter grep searches to files of the same type as the context,
--- improving search relevance and performance.
---
---@param context_bufnr number Buffer number of the context buffer
---@return string File extension without the dot, or "*" if not determinable
local function get_file_extension(context_bufnr)
  if not Utils.is_valid_buffer(context_bufnr) then
    return ""
  end

  local filename = Utils.safe_get_buffer_name(context_bufnr)
  return filename:match("%.([^%.]+)$") or "*"
end

return {
  name = "list_code_usages",
  cmds = {
    ---@param self table Tool instance with access to chat context
    ---@param args table Arguments containing symbol_name and optional file_paths
    ---@param input any Input data (unused in this tool)
    ---@param output_handler function Handler for tool output results
    function(self, args, input, output_handler)
      local symbol_name = args.symbol_name
      local file_paths = args.file_paths
      local state = {
        symbol_data = {},
        filetype = "",
      }

      if not symbol_name or symbol_name == "" then
        output_handler(Utils.create_result("error", "Symbol name is required and cannot be empty."))
        return
      end

      -- Save current state of view
      local context_winnr = self.chat.context.winnr
      local context_bufnr = self.chat.context.bufnr
      local chat_winnr = api.nvim_get_current_win()

      -- Get file extension from context buffer if available
      local file_extension = get_file_extension(context_bufnr)

      -- Exit insert mode and switch focus to context window
      vim.cmd("stopinsert")
      api.nvim_set_current_win(context_winnr)

      -- Start async processing
      SymbolFinder.find_with_lsp_async(symbol_name, file_paths, function(all_lsp_symbols)
        SymbolFinder.find_with_grep_async(symbol_name, file_extension, file_paths, function(grep_result)
          local total_results = 0
          local completed_processes = 0
          local total_processes = 2 -- LSP symbols and grep results

          local function finalize_results()
            -- Process all qflist results separately after LSP and grep processing
            local qflist = vim.fn.getqflist()
            total_results = total_results + ResultProcessor.process_quickfix_references(qflist, state.symbol_data)

            -- Handle case where we have no results
            if total_results == 0 then
              api.nvim_set_current_win(chat_winnr)
              local filetype_msg = file_extension and (" in " .. file_extension .. " files") or ""
              output_handler(
                Utils.create_result(
                  "error",
                  "Symbol not found in workspace"
                    .. filetype_msg
                    .. ". Double check the spelling and tool usage instructions."
                )
              )
              return
            end

            -- Restore original state of view
            api.nvim_set_current_buf(context_bufnr)
            api.nvim_set_current_win(chat_winnr)

            -- Store state for output handler
            ListCodeUsagesTool.symbol_data = state.symbol_data
            ListCodeUsagesTool.filetype = state.filetype

            output_handler(Utils.create_result("success", "Tool executed successfully"))
          end

          process_lsp_symbols_async(all_lsp_symbols, state, function(lsp_results_count)
            total_results = total_results + lsp_results_count
            completed_processes = completed_processes + 1

            if completed_processes == total_processes then
              finalize_results()
            end
          end)

          process_grep_results_async(grep_result, state, function(grep_results_count)
            total_results = total_results + grep_results_count
            completed_processes = completed_processes + 1

            if completed_processes == total_processes then
              finalize_results()
            end
          end)
        end)
      end)
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
          symbol_name = {
            type = "string",
            description = "The name of the symbol, such as a function name, class name, method name, variable name, etc.",
          },
          file_paths = {
            type = "array",
            description = "One or more file paths which likely contain the definition of the symbol. For instance the file which declares a class or function. This is optional but will speed up the invocation of this tool and improve the quality of its output.",
            items = {
              type = "string",
            },
          },
        },
        required = {
          "symbol_name",
        },
      },
    },
  },
  handlers = {

    ---@param _ any Unused parameter
    ---@param tools table The tools instance
    on_exit = function(_, tools)
      ListCodeUsagesTool.symbol_data = {}
      ListCodeUsagesTool.filetype = ""
    end,
  },
  output = {

    ---@param self table Tool instance containing args and other data
    ---@param tools table The tools instance
    ---@param cmd any Command data (unused)
    ---@param stdout any Standard output (unused)
    ---@return any Result of adding tool output to chat
    success = function(self, tools, cmd, stdout)
      local symbol = self.args.symbol_name
      local chat_message_content = fmt("Searched for symbol `%s`\n", symbol)

      for operation, code_blocks in pairs(ListCodeUsagesTool.symbol_data) do
        chat_message_content = chat_message_content .. fmt("\n%s:\n", operation, symbol)
        for _, code_block in ipairs(code_blocks) do
          if operation == "documentation" then
            chat_message_content = chat_message_content .. fmt("---\n%s\n", code_block.code_block)
          else
            chat_message_content = chat_message_content
              .. fmt(
                "\n---\n\nFilename: %s:%s-%s\n```%s\n%s\n```\n",
                code_block.filename,
                code_block.start_line,
                code_block.end_line,
                code_block.filetype or ListCodeUsagesTool.filetype,
                code_block.code_block
              )
          end
        end
      end

      return tools.chat:add_tool_output(self, chat_message_content)
    end,

    ---@param self table Tool instance
    ---@param tools table The tools instance
    ---@param cmd any Command data (unused)
    ---@param stderr table Array of error messages
    ---@return any Result of adding error output to chat
    error = function(self, tools, cmd, stderr)
      return tools.chat:add_tool_output(self, tostring(stderr[1]))
    end,
  },
}
