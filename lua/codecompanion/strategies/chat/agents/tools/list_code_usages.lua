local log = require("codecompanion.utils.log")

---@class CodeCompanion.Tool.ListCodeUsages: CodeCompanion.Agent.Tool
local ListCodeUsagesTool = {}

-- Constants
ListCodeUsagesTool.LSP_METHODS = {
  definition = vim.lsp.protocol.Methods.textDocument_definition,
  references = vim.lsp.protocol.Methods.textDocument_references,
  implementations = vim.lsp.protocol.Methods.textDocument_implementation,
  declaration = vim.lsp.protocol.Methods.textDocument_declaration,
  type_definition = vim.lsp.protocol.Methods.textDocument_typeDefinition,
  documentation = vim.lsp.protocol.Methods.textDocument_hover,
}

ListCodeUsagesTool.LSP_TIMEOUT_MS = 60000
ListCodeUsagesTool.TREESITTER_NODES = {
  -- Class-level constructs (highest priority)
  class_definition = 30,
  class_declaration = 30,
  interface_declaration = 30,
  impl_item = 30,
  struct_item = 30,
  trait_item = 30,
  enum_item = 30,
  enum_declaration = 30,
  type_item = 30,
  module_definition = 30,
  namespace_definition = 30,
  expression_statement = 30,

  -- Function-level constructs (medium priority)
  function_definition = 20,
  function_declaration = 20,
  method_definition = 20,
  method_declaration = 20,
  function_item = 20,
  constructor_declaration = 20,

  -- Variable/field declarations (lower priority)
  variable_declaration = 10,
  field_declaration = 10,
  property_declaration = 10,
  const_declaration = 10,
  let_declaration = 10,
  const_item = 10,
  local_declaration = 10,
  assignment_statement = 10,

  -- Import statements
  import_declaration = 5,
  use_declaration = 5,

  -- Other constructs
  decorated_definition = 15,
  static_item = 15,
  attribute_item = 10,
  type_declaration = 15,
}

-- State variables
ListCodeUsagesTool.symbol_data = {}
ListCodeUsagesTool.filetype = ""

----------------------
-- Symbol Finding Functions
----------------------

-- Find symbol using grep and populate quickfix list
function ListCodeUsagesTool:find_symbol_with_grep(symbolName, file_extension, filepaths)
  local search_pattern = vim.fn.escape(symbolName, "\\")
  local cmd = "silent! grep! -w"

  -- Default excluded directories if none provided. Should be excluded by default in gitignore.
  local exclude_dirs = { "node_modules", "dist", "vendor", ".git", "venv", ".env", "target", "build" }

  if file_extension and file_extension ~= "" then
    cmd = cmd .. " --glob=" .. vim.fn.shellescape("*." .. file_extension) .. " "
  end

  -- Add exclusion patterns for directories
  for _, dir in ipairs(exclude_dirs) do
    cmd = cmd .. " --glob=!" .. vim.fn.shellescape(dir .. "/**") .. " "
  end

  cmd = cmd .. vim.fn.shellescape(search_pattern)

  if filepaths and type(filepaths) == "table" and #filepaths > 0 then
    cmd = cmd .. " " .. table.concat(filepaths, " ")
  end

  log:debug("[ListCodeUsagesTool:find_symbol_with_grep] Executing grep command: %s", cmd)

  ---@diagnostic disable-next-line: param-type-mismatch
  local success, _ = pcall(vim.cmd, cmd)
  if not success then
    return nil
  end

  log:debug(
    "[ListCodeUsagesTool:find_symbol_with_grep] Found %d matches for '%s'",
    vim.fn.getqflist({ size = 0 }).size,
    symbolName
  )
  local qflist = vim.fn.getqflist()
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
    qflist = qflist, -- Save quickfix list for later
  }
end

-- Check if code block A is enclosed by code block B
function ListCodeUsagesTool:is_enclosed_by(block_a, block_b)
  if block_a.filename ~= block_b.filename then
    return false
  end
  return block_a.start_line >= block_b.start_line and block_a.end_line <= block_b.end_line
end

-- Enhanced duplicate/enclosure checking for process_lsp_item
function ListCodeUsagesTool:is_duplicate_or_enclosed(new_block)
  for op_type, blocks in pairs(self.symbol_data) do
    for _, existing_block in ipairs(blocks) do
      -- Skip if missing filename or line data (like documentation)
      if not (existing_block.filename and existing_block.start_line and existing_block.end_line) then
        goto continue
      end

      if
        new_block.filename == existing_block.filename
        and new_block.start_line == existing_block.start_line
        and new_block.end_line == existing_block.end_line
      then
        log:debug(
          "[ListCodeUsagesTool:is_duplicate_or_enclosed] Found exact duplicate: %s:%d-%d",
          existing_block.filename,
          existing_block.start_line,
          existing_block.end_line
        )
        return true
      end

      if self:is_enclosed_by(new_block, existing_block) then
        log:debug(
          "[ListCodeUsagesTool:is_duplicate_or_enclosed] Found enclosed block: %s:%d-%d is enclosed by %s:%d-%d",
          new_block.filename,
          new_block.start_line,
          new_block.end_line,
          existing_block.filename,
          existing_block.start_line,
          existing_block.end_line
        )
        return true
      end

      ::continue::
    end
  end
  return false
end

-- get all matching symbols from lsp
function ListCodeUsagesTool:get_all_symbols_with_lsp(symbolName, filepaths)
  log:debug("[ListCodeUsagesTool:get_all_symbols_with_lsp] Searching for all symbols '%s' using LSP", symbolName)

  local clients = vim.lsp.get_clients({
    method = vim.lsp.protocol.Methods.workspace_symbol,
  })

  if #clients == 0 then
    return {}
  end

  local symbols = {}
  for _, client in ipairs(clients) do
    local params = { query = symbolName }
    local result = client:request_sync(vim.lsp.protocol.Methods.workspace_symbol, params, self.LSP_TIMEOUT_MS)

    if result and result.result then
      for _, symbol in ipairs(result.result) do
        if symbol.name == symbolName then
          local uri = symbol.location.uri
          local range = symbol.location.range
          local filepath = uri:gsub("file://", "")

          -- Filter by filepaths if specified
          if filepaths and #filepaths > 0 then
            local match = false
            for _, pattern in ipairs(filepaths) do
              if filepath:find(pattern) then
                match = true
                break
              end
            end
            if not match then
              goto continue
            end
          end

          table.insert(symbols, {
            uri = uri,
            range = range,
            name = symbol.name,
            kind = symbol.kind,
            file = filepath,
          })

          ::continue::
        end
      end
    end
  end

  -- Sort symbols by kind to prioritize definitions
  table.sort(symbols, function(a, b)
    return (a.kind or 999) < (b.kind or 999)
  end)

  return symbols
end
-- Find symbol using LSP workspace/symbol
function ListCodeUsagesTool:find_symbol_with_lsp(symbolName, filepaths)
  log:debug("[ListCodeUsagesTool:find_symbol_with_lsp] Searching for symbol '%s' using LSP", symbolName)

  local clients = vim.lsp.get_clients({
    method = vim.lsp.protocol.Methods.workspace_symbol,
  })

  if #clients == 0 then
    return nil
  end

  local symbols = {}
  for _, client in ipairs(clients) do
    local params = { query = symbolName }
    local result = client:request_sync(vim.lsp.protocol.Methods.workspace_symbol, params, self.LSP_TIMEOUT_MS)
    log:debug(
      "[ListCodeUsagesTool:find_symbol_with_lsp] LSP client %s returned workspace/symbol result: %s",
      client.name,
      vim.inspect(result)
    )

    if result and result.result then
      for _, symbol in ipairs(result.result) do
        if symbol.name == symbolName then
          local uri = symbol.location.uri
          local range = symbol.location.range
          local filepath = uri:gsub("file://", "")

          -- Filter by filepaths if specified
          if filepaths and #filepaths > 0 then
            local match = false
            for _, pattern in ipairs(filepaths) do
              if filepath:find(pattern) then
                match = true
                break
              end
            end
            if not match then
              goto continue
            end
          end

          table.insert(symbols, {
            file = filepath,
            line = range.start.line + 1,
            col = range.start.character,
            text = symbol.name,
            name = symbol.name,
            kind = symbol.kind,
          })

          ::continue::
        end
      end
    end
  end

  if #symbols > 0 then
    -- Sort symbols by kind to prioritize definitions
    table.sort(symbols, function(a, b)
      return (a.kind or 999) < (b.kind or 999)
    end)

    return symbols[1]
  end

  return nil
end

-- Open file and set cursor position
function ListCodeUsagesTool:open_file_and_set_cursor(filepath, line, col)
  log:debug("[ListCodeUsagesTool:open_file_and_set_cursor] Opening file: %s at line: %d, col: %d", filepath, line, col)
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  vim.api.nvim_win_set_cursor(0, { line, col })
  vim.cmd("normal! zz")
  return true
end

-- Find and navigate to a symbol in workspace
function ListCodeUsagesTool:navigate_to_symbol(symbolName, file_extension, filepaths)
  local symbol_result = self:find_symbol_with_lsp(symbolName, filepaths)
  local grep_result = self:find_symbol_with_grep(symbolName, file_extension, filepaths)

  if not symbol_result then
    if grep_result then
      -- get first match from qflist
      symbol_result = grep_result
      -- Save all qflist results for grep references operation
      symbol_result.all_qflist = grep_result.qflist
    end
  end

  if not symbol_result then
    local filetype_msg = file_extension and (" in " .. file_extension .. " files") or ""
    return {
      status = "error",
      data = "Symbol not found in workspace"
        .. filetype_msg
        .. ". Double check the spelling and tool usage instructions.",
      qflist = nil,
    }
  end

  local success = self:open_file_and_set_cursor(symbol_result.file, symbol_result.line, symbol_result.col)

  if success then
    return {
      status = "success",
      data = { bufnr = symbol_result.bufnr },
      qflist = symbol_result.qflist,
    }
  else
    return {
      status = "error",
      data = "Failed to open file or set cursor position.",
      qflist = nil,
    }
  end
end

----------------------
-- Code Extraction Functions
----------------------

function ListCodeUsagesTool:get_symbol_at_position(bufnr, row, col)
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return { status = "error", data = "Invalid buffer id: " .. bufnr }
  end

  local parser = vim.treesitter.get_parser(bufnr)
  if not parser then
    return self:get_fallback_symbol(bufnr, row, col) -- Use fallback if no parser
  end

  local tree = parser:parse()[1]
  if not tree then
    return self:get_fallback_symbol(bufnr, row, col) -- Use fallback if no tree
  end

  local root = tree:root()
  local node = root:named_descendant_for_range(row, col, row, col)

  -- Find the node with highest priority
  local best_node = nil
  local highest_priority = 0

  while node do
    local node_type = node:type()
    log:debug("[ListCodeUsagesTool:get_symbol_at_position] Checking node type: %s", node_type)
    local priority = self.TREESITTER_NODES[node_type] or 0

    if priority > highest_priority then
      highest_priority = priority
      best_node = node
    end
    node = node:parent()
  end

  if best_node then
    return self:extract_node_data(bufnr, best_node)
  end

  -- Fallback if no suitable node found
  return self:get_fallback_symbol(bufnr, row, col)
end

-- Fallback method for when TreeSitter doesn't provide what we need
function ListCodeUsagesTool:get_fallback_symbol(bufnr, row, col)
  log:debug(
    "[ListCodeUsagesTool:get_fallback_symbol] Using fallback extraction for buffer %d at (%d, %d)",
    bufnr,
    row,
    col
  )

  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if not line then
    return { status = "error", data = "No text at specified position" }
  end

  -- Simple indentation-based extraction
  local indent_pattern = "^(%s*)"
  local indent = line:match(indent_pattern):len()

  -- Find start of block (going upward)
  local start_row = row
  for i = row - 1, 0, -1 do
    local curr_line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
    if not curr_line then
      break
    end

    local curr_indent = curr_line:match(indent_pattern):len()
    if curr_indent < indent and not curr_line:match("^%s*$") and not curr_line:match("^%s*[//#*-]") then
      break
    end
    start_row = i
  end

  -- Find end of block (going downward)
  local end_row = row
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  for i = row + 1, math.min(row + 100, total_lines - 1) do
    local curr_line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
    if not curr_line then
      break
    end

    local curr_indent = curr_line:match(indent_pattern):len()
    if curr_indent < indent and not curr_line:match("^%s*$") then
      break
    end
    end_row = i
  end

  -- Look for comments above the start position
  local comment_start = start_row
  for i = start_row - 1, math.max(0, start_row - 10), -1 do
    local curr_line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
    if not curr_line then
      break
    end

    if curr_line:match("^%s*$") then
      break -- Stop at blank line
    elseif curr_line:match("^%s*[//#*-]") then
      comment_start = i -- This is a comment line
    else
      break -- Not a comment line
    end
  end

  -- Extract the code block
  local lines = vim.api.nvim_buf_get_lines(bufnr, comment_start, end_row + 1, false)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })

  return {
    status = "success",
    data = {
      code_block = table.concat(lines, "\n"),
      start_line = comment_start + 1,
      end_line = end_row + 1,
      filename = filename,
      filetype = filetype,
    },
  }
end

-- Enhanced function to extract node data including comments
function ListCodeUsagesTool:extract_node_data(bufnr, node)
  local start_row, start_col, end_row, end_col = node:range()
  log:debug(
    "[ListCodeUsagesTool:extract_node_data] Extracting node from buffer %d, range: (%d, %d) to (%d, %d)",
    bufnr,
    start_row,
    start_col,
    end_row,
    end_col
  )

  -- Look for comments above the node
  local comment_start = start_row
  for i = start_row - 1, math.max(0, start_row - 10), -1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
    if not line then
      break
    end

    if line:match("^%s*$") then
      break -- Stop at blank line
    elseif line:match("^%s*[//#*-]") then
      comment_start = i -- This is a comment line
    else
      break -- Not a comment line
    end
  end

  -- Get lines including comments
  local lines = vim.api.nvim_buf_get_lines(bufnr, comment_start, end_row + 1, false)
  if not lines or #lines == 0 then
    return { status = "error", data = "Symbol text range is empty." }
  end

  -- Adjust first line if it's part of the node (not a comment)
  if start_row == comment_start then
    lines[1] = lines[1]:sub(start_col + 1)
  end

  -- Adjust last line
  lines[#lines] = lines[#lines]:sub(1, end_col)

  local code_block = table.concat(lines, "\n")
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })

  return {
    status = "success",
    data = {
      code_block = code_block,
      start_line = comment_start + 1, -- 1-indexed line numbers
      end_line = end_row + 1, -- 1-indexed line numbers
      filename = filename,
      filetype = filetype,
    },
  }
end

----------------------
-- LSP Functions
----------------------

-- Filter references to only include those in the project directory
function ListCodeUsagesTool:filter_project_references(references)
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
    "[ListCodeUsagesTool:filter_project_references] References filtered. Original: %d, Filtered: %d",
    #references,
    #filtered_results
  )

  return filtered_results
end

-- Execute an LSP request on the current buffer
function ListCodeUsagesTool:execute_lsp_request(bufnr, method)
  local clients = vim.lsp.get_clients({ method = method })
  local lsp_results = {}

  for _, client in ipairs(clients) do
    if not vim.lsp.buf_is_attached(bufnr, client.id) then
      log:debug(
        "[ListCodeUsagesTool:execute_lsp_request] Attaching client %s to buffer %d for method %s",
        client.name,
        bufnr,
        method
      )
      vim.lsp.buf_attach_client(bufnr, client.id)
    end

    local position_params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    ---@diagnostic disable-next-line: inject-field
    position_params.context = { includeDeclaration = false }

    local lsp_result = client:request_sync(method, position_params, self.LSP_TIMEOUT_MS)

    log:debug(
      "[ListCodeUsagesTool:execute_lsp_request] Client %s returned result for method %s: %s",
      client.name,
      method,
      vim.inspect(lsp_result)
    )
    if lsp_result and lsp_result.result then
      -- Handle hover documentation specially
      if method == self.LSP_METHODS.documentation and lsp_result.result.contents then
        lsp_result.result = {
          range = lsp_result.result.range,
          contents = lsp_result.result.contents.value or lsp_result.result.contents,
        }
      end

      -- For references, filter to just project references
      if method == self.LSP_METHODS.references and type(lsp_result.result) == "table" then
        lsp_results[client.name] = self:filter_project_references(lsp_result.result)
      else
        lsp_results[client.name] = lsp_result.result
      end
    end
  end

  return lsp_results
end

-- Process a single LSP result item
function ListCodeUsagesTool:process_lsp_item(uri, range, operation)
  if not (uri and range) then
    return { status = "error", data = "Missing uri or range" }
  end

  local target_bufnr = vim.uri_to_bufnr(uri)
  vim.fn.bufload(target_bufnr)

  local symbol_result = self:get_symbol_at_position(target_bufnr, range.start.line, range.start.character)
  if symbol_result.status ~= "success" then
    return symbol_result
  end

  if self:is_duplicate_or_enclosed(symbol_result.data) then
    return { status = "success", data = "Duplicate or enclosed entry" }
  end

  -- Add to results
  if not self.symbol_data[operation] then
    self.symbol_data[operation] = {}
  end
  table.insert(self.symbol_data[operation], symbol_result.data)

  return { status = "success", data = "Symbol processed" }
end

-- Process LSP results
function ListCodeUsagesTool:process_lsp_results(lsp_results, operation)
  local processed_count = 0

  for _, result in pairs(lsp_results) do
    -- Handle documentation specially
    if result.contents then
      if not self.symbol_data[operation] then
        self.symbol_data[operation] = {}
      end

      local content = result.contents
      -- jdtls puts documentation in a table with a single string
      if type(content) == "table" and type(content[#content]) == "string" then
        content = content[#content]
      end

      table.insert(self.symbol_data[operation], { code_block = content })
      processed_count = processed_count + 1
    -- Handle single item with range
    elseif result.range then
      local process_result = self:process_lsp_item(result.uri or result.targetUri, result.range, operation)
      if process_result.status == "success" then
        processed_count = processed_count + 1
      end
    -- Handle array of items
    else
      for _, item in pairs(result) do
        local process_result =
          self:process_lsp_item(item.uri or item.targetUri, item.range or item.targetSelectionRange, operation)
        if process_result.status == "success" and process_result.data ~= "Duplicate entry" then
          processed_count = processed_count + 1
        end
      end
    end
  end

  return processed_count
end

-- Process code references from quickfix list
function ListCodeUsagesTool:process_quickfix_references(qflist)
  if not qflist or #qflist == 0 then
    return 0
  end

  log:debug("[ListCodeUsagesTool:process_quickfix_references] Processing %d quickfix items", #qflist)
  local processed_count = 0

  for _, qfitem in ipairs(qflist) do
    if qfitem.bufnr and qfitem.lnum then
      local target_bufnr = qfitem.bufnr
      local row = qfitem.lnum - 1 -- Convert to 0-indexed
      local col = qfitem.col - 1 -- Convert to 0-indexed

      -- Load buffer if needed
      if not vim.api.nvim_buf_is_loaded(target_bufnr) then
        vim.fn.bufload(target_bufnr)
      end

      -- Extract code block using treesitter
      local symbol_result = self:get_symbol_at_position(target_bufnr, row, col)

      if symbol_result.status == "success" then
        -- Initialize references array if needed
        if not self.symbol_data["grep"] then
          self.symbol_data["grep"] = {}
        end

        local duplicate = false
        if self:is_duplicate_or_enclosed(symbol_result.data) then
          duplicate = true
          break
        end

        if not duplicate then
          table.insert(self.symbol_data["grep"], symbol_result.data)
          processed_count = processed_count + 1
        end
      end
    end
  end

  return processed_count
end

----------------------
-- Main Tool Implementation
----------------------

return {
  name = "list_code_usages",
  cmds = {
    function(self, args, input)
      local symbolName = args.symbolName
      local filePaths = args.filePaths

      if not symbolName or symbolName == "" then
        return {
          status = "error",
          data = "Symbol name is required and cannot be empty.",
        }
      end

      -- save current state of view
      local context_winnr = self.chat.context.winnr
      local context_bufnr = self.chat.context.bufnr
      local chat_winnr = vim.api.nvim_get_current_win()

      -- get file extension from context buffer if available. It will be later used as glob param for grep.
      local file_extension = ""
      if context_bufnr and vim.api.nvim_buf_is_valid(context_bufnr) then
        local filename = vim.api.nvim_buf_get_name(context_bufnr)
        file_extension = filename:match("%.([^%.]+)$") or "*"
      end

      -- reset tool state
      ListCodeUsagesTool.symbol_data = {}
      ListCodeUsagesTool.filetype = ""

      -- exit insert mode and switch foxus to context window
      vim.cmd("stopinsert")
      vim.api.nvim_set_current_win(context_winnr)

      -- step 1: navigate to the symbol position in workspace
      local cursor_result = ListCodeUsagesTool:navigate_to_symbol(symbolName, file_extension, filePaths)

      if cursor_result.status == "error" then
        vim.api.nvim_set_current_win(chat_winnr)
        return cursor_result
      end

      local bufnr = tonumber(cursor_result.data.bufnr)
      local results_count = 0
      -- Step 2: Process all symbols found by LSP
      local all_lsp_symbols = ListCodeUsagesTool:get_all_symbols_with_lsp(symbolName, filePaths)
      for _, symbol in ipairs(all_lsp_symbols) do
        local process_result = ListCodeUsagesTool:process_lsp_item(symbol.uri, symbol.range, "definition")
        if process_result.status == "success" and process_result.data ~= "Duplicate or enclosed entry" then
          results_count = results_count + 1
        end
      end

      -- Step 3: Proces qflist result as grep operation if it isn't a duplicate with LSP results.
      if cursor_result.qflist then
        results_count = ListCodeUsagesTool:process_quickfix_references(cursor_result.qflist)
      end

      -- Restore original state of view
      vim.api.nvim_set_current_buf(context_bufnr)
      vim.api.nvim_set_current_win(chat_winnr)

      if results_count > 0 then
        ListCodeUsagesTool.filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
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
    on_exit = function(_, agent)
      ListCodeUsagesTool.symbol_data = {}
      ListCodeUsagesTool.filetype = ""
    end,
  },
  output = {
    success = function(self, agent, cmd, stdout)
      local symbol = self.args.symbolName
      local chat_message_content = ""

      for operation, code_blocks in pairs(ListCodeUsagesTool.symbol_data) do
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
                code_block.filetype or ListCodeUsagesTool.filetype,
                code_block.code_block
              )
          end
        end
      end

      return agent.chat:add_tool_output(self, chat_message_content)
    end,

    error = function(self, agent, cmd, stderr, stdout)
      return agent.chat:add_tool_output(self, tostring(stderr[1]))
    end,
  },
}
