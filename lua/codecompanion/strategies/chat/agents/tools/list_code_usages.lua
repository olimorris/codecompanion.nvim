local log = require("codecompanion.utils.log")

---@class CodeCompanion.Tool.ListCodeUsages: CodeCompanion.Agent.Tool
local ListCodeUsagesTool = {}

-----------------------
-- Constants
-----------------------
local CONSTANTS = {
  LSP_TIMEOUT_MS = 60000,
  MAX_BLOCK_SCAN_LINES = 100,
  MAX_COMMENT_LINES = 10,
  LSP_METHODS = {
    definition = vim.lsp.protocol.Methods.textDocument_definition,
    references = vim.lsp.protocol.Methods.textDocument_references,
    implementations = vim.lsp.protocol.Methods.textDocument_implementation,
    declaration = vim.lsp.protocol.Methods.textDocument_declaration,
    type_definition = vim.lsp.protocol.Methods.textDocument_typeDefinition,
    documentation = vim.lsp.protocol.Methods.textDocument_hover,
  },
  EXCLUDED_DIRS = { "node_modules", "dist", "vendor", ".git", "venv", ".env", "target", "build" },
}

-----------------------
-- Utility Functions
-----------------------
local Utils = {}

-- Create a result object with standard format
function Utils.create_result(status, data)
  return { status = status, data = data }
end

-- Convert URI to filepath
function Utils.uri_to_filepath(uri)
  return uri and uri:gsub("file://", "") or ""
end

-- Convert absolute path to relative path based on cwd
function Utils.make_relative_path(filepath)
  if not filepath or filepath == "" then
    return ""
  end

  local cwd = vim.fn.getcwd()

  -- Normalize paths to handle different separators
  local normalized_cwd = cwd:gsub("\\", "/")
  local normalized_filepath = filepath:gsub("\\", "/")

  -- Ensure cwd ends with separator for proper matching
  if not normalized_cwd:match("/$") then
    normalized_cwd = normalized_cwd .. "/"
  end

  -- Check if filepath starts with cwd
  if normalized_filepath:find(normalized_cwd, 1, true) == 1 then
    -- Return relative path
    return normalized_filepath:sub(#normalized_cwd + 1)
  else
    -- If not within cwd, return just the filename
    return normalized_filepath:match("([^/]+)$") or normalized_filepath
  end
end

-- Check if a file is within project directory
function Utils.is_in_project(filepath)
  local project_root = vim.fn.getcwd()
  return filepath:find(project_root, 1, true) == 1
end

-- Safe buffer validation
function Utils.is_valid_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

-- Safe filetype retrieval
function Utils.safe_get_filetype(bufnr)
  if not Utils.is_valid_buffer(bufnr) then
    return ""
  end

  local success, filetype = pcall(vim.api.nvim_get_option_value, "filetype", { buf = bufnr })
  return success and filetype or ""
end

-- Safe buffer name retrieval
function Utils.safe_get_buffer_name(bufnr)
  if not Utils.is_valid_buffer(bufnr) then
    return ""
  end

  local success, name = pcall(vim.api.nvim_buf_get_name, bufnr)
  return success and name or ""
end

-- Safe line retrieval
function Utils.safe_get_lines(bufnr, start_row, end_row, strict_indexing)
  if not Utils.is_valid_buffer(bufnr) then
    return {}
  end

  local success, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, start_row, end_row, strict_indexing or false)
  return success and lines or {}
end

-- Open file and position cursor
function Utils.open_file_and_set_cursor(filepath, line, col)
  log:debug("[Utils:open_file_and_set_cursor] Opening file: %s at line: %d, col: %d", filepath, line, col)

---@diagnostic disable-next-line: param-type-mismatch
  local success, _ = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(filepath))
  if not success then
    return false
  end

  local cursor_success, _ = pcall(vim.api.nvim_win_set_cursor, 0, { line, col })
  if cursor_success then
---@diagnostic disable-next-line: param-type-mismatch
    pcall(vim.cmd, "normal! zz")
  end

  return true
end

-- Check if code block A is enclosed by code block B
function Utils.is_enclosed_by(block_a, block_b)
  if block_a.filename ~= block_b.filename then
    return false
  end
  return block_a.start_line >= block_b.start_line and block_a.end_line <= block_b.end_line
end

-----------------------
-- Symbol Finding
-----------------------
local SymbolFinder = {}

function SymbolFinder.find_with_lsp(symbolName, filepaths)
  local clients = vim.lsp.get_clients({
    method = vim.lsp.protocol.Methods.workspace_symbol,
  })

  if #clients == 0 then
    return {}
  end

  local symbols = {}
  for _, client in ipairs(clients) do
    local params = { query = symbolName }
    local result = client:request_sync(vim.lsp.protocol.Methods.workspace_symbol, params, CONSTANTS.LSP_TIMEOUT_MS)

    if result and result.result then
      for _, symbol in ipairs(result.result) do
        if symbol.name == symbolName then
          local filepath = Utils.uri_to_filepath(symbol.location.uri)

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
            uri = symbol.location.uri,
            range = symbol.location.range,
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

  log:debug("[SymbolFinder:find_with_lsp] Found symbols with LSP:\n %s", vim.inspect(symbols))
  return symbols
end

-- Find symbol using grep and populate quickfix list
function SymbolFinder.find_with_grep(symbolName, file_extension, filepaths)
  local search_pattern = vim.fn.escape(symbolName, "\\")
  local cmd = "silent! grep! -w"

  -- Add file extension filter if provided
  if file_extension and file_extension ~= "" then
    cmd = cmd .. " --glob=" .. vim.fn.shellescape("*." .. file_extension) .. " "
  end

  -- Add exclusion patterns for directories
  for _, dir in ipairs(CONSTANTS.EXCLUDED_DIRS) do
    cmd = cmd .. " --glob=!" .. vim.fn.shellescape(dir .. "/**") .. " "
  end

  cmd = cmd .. vim.fn.shellescape(search_pattern)

  -- Add file paths if provided
  if filepaths and type(filepaths) == "table" and #filepaths > 0 then
    cmd = cmd .. " " .. table.concat(filepaths, " ")
  end

  log:debug("[SymbolFinder:find_with_grep] Executing grep command: %s", cmd)

  ---@diagnostic disable-next-line: param-type-mismatch
  local success, _ = pcall(vim.cmd, cmd)
  if not success then
    return nil
  end

  local qflist = vim.fn.getqflist()
  if #qflist == 0 then
    return nil
  end

  log:debug("[SymbolFinder:find_with_grep] Found grep matches: \n %s", vim.inspect(qflist))

  local first_match = qflist[1]
  return {
    file = vim.fn.bufname(first_match.bufnr),
    line = first_match.lnum,
    col = first_match.col,
    text = first_match.text,
    bufnr = first_match.bufnr,
    qflist = qflist,
  }
end

-----------------------
-- Code Extraction
-----------------------
local CodeExtractor = {}

function CodeExtractor.get_block_with_locals(bufnr, row, col)
  local success, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not success or not parser then
    return nil
  end

  local trees = parser:parse()
  log:debug("[CodeExtractor:get_block_with_locals] Parsed %d treesitter trees.", #trees)
  if not trees or #trees == 0 then
    return nil
  end

  -- Find the node at the cursor position
  local tree = trees[1]
  local root = tree:root()
  local node = root:named_descendant_for_range(row, col, row, col)

  if not node then
    return nil
  end

  -- Get the locals query for this language
  local query = vim.treesitter.query.get(parser:lang(), "locals")
  if not query then
    log:debug("[CodeExtractor:get_block_with_locals] No locals query for language: %s", parser:lang())
    return node
  end

  -- Find all scopes in the file
  local scopes = {}
  local target_node = node

  -- First pass: find all scopes and possibly the exact symbol node
  for _, tree in ipairs(trees) do
    for id, found_node, meta in query:iter_captures(tree:root(), bufnr) do
      local capture_name = query.captures[id]
      if capture_name == "local.scope" then
        table.insert(scopes, {
          node = found_node,
          range = { found_node:range() },
        })
      end
    end
  end

  log:debug("[CodeExtractor:get_block_with_locals] Found %d scopes in the file", #scopes)

  -- Simple helper function to check node type
  local function matches_any(node_type, patterns)
    for _, pattern in ipairs(patterns) do
      if node_type:match(pattern) then
        return true
      end
    end
    return false
  end

  -- Get target position for scope matching
  local target_start_row, target_start_col, target_end_row, target_end_col = target_node:range()

  -- Find the smallest scope that contains the target node
  local best_scope = nil
  local best_scope_size = math.huge

  for _, scope in ipairs(scopes) do
    local start_row, start_col, end_row, end_col = unpack(scope.range)

    -- Check if the scope contains the target
    if
      (start_row < target_start_row or (start_row == target_start_row and start_col <= target_start_col))
      and (end_row > target_end_row or (end_row == target_end_row and end_col >= target_end_col))
    then
      -- Calculate scope size (approximate number of characters)
      local scope_size = (end_row - start_row) * 100 + (end_col - start_col)

      -- Check if this scope is significant (function, class, etc.)
      local scope_node_type = scope.node:type()
      local is_significant = matches_any(scope_node_type, {
        "function",
        "method",
        "procedure",
        "def",
        "class",
        "interface",
        "struct",
        "enum",
        "module",
        "namespace",
        "type",
      })

      -- Only consider significant scopes, and prefer smaller ones
      if is_significant and scope_size < best_scope_size then
        best_scope = scope.node
        best_scope_size = scope_size
        log:debug(
          "[CodeExtractor:get_block_with_locals] Found containing scope: %s (size: %d)",
          scope_node_type,
          scope_size
        )
      end
    end
  end

  -- If we found a suitable scope, return it
  if best_scope then
    log:debug("[CodeExtractor:get_block_with_locals] Using best scope: %s", best_scope:type())
    return best_scope
  end

  -- Walk up the tree to find the first significant enclosing block
  local current = target_node
  while current do
    local current_type = current:type()

    -- Check for function-like nodes
    if matches_any(current_type, { "function", "method", "procedure", "def" }) then
      log:debug("[CodeExtractor:get_block_with_locals] Found enclosing function: %s", current_type)
      return current
    end

    -- Check for class-like nodes
    if matches_any(current_type, { "class", "interface", "struct", "enum" }) then
      log:debug("[CodeExtractor:get_block_with_locals] Found enclosing class: %s", current_type)
      return current
    end

    -- Move up to parent
    current = current:parent()
  end

  -- If we didn't find a significant block, return the original node
  return target_node
end

-- Extract node data including comments
function CodeExtractor.extract_node_data(bufnr, node)
  local start_row, start_col, end_row, end_col = node:range()

  local lines = Utils.safe_get_lines(bufnr, start_row, end_row + 1)
  if not lines or #lines == 0 then
    return Utils.create_result("error", "Symbol text range is empty.")
  end

  -- Adjust last line
  lines[#lines] = lines[#lines]:sub(1, end_col)

  local code_block = table.concat(lines, "\n")
  local absolute_filename = Utils.safe_get_buffer_name(bufnr)
  local relative_filename = Utils.make_relative_path(absolute_filename)
  local filetype = Utils.safe_get_filetype(bufnr)

  return Utils.create_result("success", {
    code_block = code_block,
    start_line = start_row + 1, -- 1-indexed line numbers
    end_line = end_row + 1, -- 1-indexed line numbers
    filename = relative_filename,
    filetype = filetype,
  })
end

-- Fallback method for when TreeSitter doesn't provide what we need
function CodeExtractor.get_fallback_code_block(bufnr, row, col)
  local lines = Utils.safe_get_lines(bufnr, row, row + 1)
  local line = lines[1]
  if not line then
    return Utils.create_result("error", "No text at specified position")
  end

  -- Simple indentation-based extraction
  local indent_pattern = "^(%s*)"
  local indent = line:match(indent_pattern):len()

  -- Find start of block (going upward)
  local start_row = row
  for i = row - 1, 0, -1 do
    local curr_lines = Utils.safe_get_lines(bufnr, i, i + 1)
    local curr_line = curr_lines[1]
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
  for i = row + 1, math.min(row + CONSTANTS.MAX_BLOCK_SCAN_LINES, total_lines - 1) do
    local curr_lines = Utils.safe_get_lines(bufnr, i, i + 1)
    local curr_line = curr_lines[1]
    if not curr_line then
      break
    end

    local curr_indent = curr_line:match(indent_pattern):len()
    if curr_indent < indent and not curr_line:match("^%s*$") then
      break
    end
    end_row = i
  end

  -- Extract the code block
  local extracted_lines = Utils.safe_get_lines(bufnr, start_row, end_row + 1)
  local absolute_filename = Utils.safe_get_buffer_name(bufnr)
  local relative_filename = Utils.make_relative_path(absolute_filename)
  local filetype = Utils.safe_get_filetype(bufnr)

  return Utils.create_result("success", {
    code_block = table.concat(extracted_lines, "\n"),
    start_line = start_row + 1,
    end_line = end_row + 1,
    filename = relative_filename,
    filetype = filetype,
  })
end

-- Main function to get code block at position
function CodeExtractor.get_code_block_at_position(bufnr, row, col)
  if not Utils.is_valid_buffer(bufnr) then
    return Utils.create_result("error", "Invalid buffer id: " .. tostring(bufnr))
  end

  local node = CodeExtractor.get_block_with_locals(bufnr, row, col)

  if node then
    return CodeExtractor.extract_node_data(bufnr, node)
  else
    return CodeExtractor.get_fallback_code_block(bufnr, row, col)
  end
end

-----------------------
-- LSP Handling
-----------------------
local LspHandler = {}

-- Filter references to only include those in the project directory
function LspHandler.filter_project_references(references)
  local filtered_results = {}

  for _, reference in ipairs(references) do
    local uri = reference.uri
    if uri then
      local filepath = Utils.uri_to_filepath(uri)
      if Utils.is_in_project(filepath) then
        table.insert(filtered_results, reference)
      end
    end
  end

  log:debug(
    "[LspHandler:filter_project_references] References filtered. Original: %d, Filtered: %d",
    #references,
    #filtered_results
  )

  return filtered_results
end

-- Execute an LSP request on the current buffer
function LspHandler.execute_request(bufnr, method)
  local clients = vim.lsp.get_clients({ method = method })
  local lsp_results = {}

  for _, client in ipairs(clients) do
    if not vim.lsp.buf_is_attached(bufnr, client.id) then
      log:debug(
        "[LspHandler:execute_request] Attaching client %s to buffer %d for method %s",
        client.name,
        bufnr,
        method
      )
      vim.lsp.buf_attach_client(bufnr, client.id)
    end

    local position_params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    position_params.context = { includeDeclaration = false }

    local lsp_result = client:request_sync(method, position_params, CONSTANTS.LSP_TIMEOUT_MS)

    if lsp_result and lsp_result.result then
      -- Handle hover documentation specially
      if method == CONSTANTS.LSP_METHODS.documentation and lsp_result.result.contents then
        lsp_result.result = {
          range = lsp_result.result.range,
          contents = lsp_result.result.contents.value or lsp_result.result.contents,
        }
      end

      -- For references, filter to just project references
      if method == CONSTANTS.LSP_METHODS.references and type(lsp_result.result) == "table" then
        lsp_results[client.name] = LspHandler.filter_project_references(lsp_result.result)
      else
        lsp_results[client.name] = lsp_result.result
      end
    end
  end

  return lsp_results
end

-----------------------
-- Result Processing
-----------------------
local ResultProcessor = {}

-- Check if a block is a duplicate or enclosed by existing blocks
function ResultProcessor.is_duplicate_or_enclosed(new_block, symbol_data)
  for op_type, blocks in pairs(symbol_data) do
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
          "[ResultProcessor:is_duplicate_or_enclosed] Found exact duplicate: %s:%d-%d",
          existing_block.filename,
          existing_block.start_line,
          existing_block.end_line
        )
        return true
      end

      if Utils.is_enclosed_by(new_block, existing_block) then
        log:debug(
          "[ResultProcessor:is_duplicate_or_enclosed] Found enclosed block: %s:%d-%d is enclosed by %s:%d-%d",
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

-- Process a single LSP result item
function ResultProcessor.process_lsp_item(uri, range, operation, symbol_data)
  if not (uri and range) then
    return Utils.create_result("error", "Missing uri or range")
  end

  local target_bufnr = vim.uri_to_bufnr(uri)
  vim.fn.bufload(target_bufnr)

  local symbol_result = CodeExtractor.get_code_block_at_position(target_bufnr, range.start.line, range.start.character)

  if symbol_result.status ~= "success" then
    return symbol_result
  end

  if ResultProcessor.is_duplicate_or_enclosed(symbol_result.data, symbol_data) then
    return Utils.create_result("success", "Duplicate or enclosed entry")
  end

  -- Add to results
  if not symbol_data[operation] then
    symbol_data[operation] = {}
  end
  table.insert(symbol_data[operation], symbol_result.data)

  return Utils.create_result("success", "Symbol processed")
end

function ResultProcessor.process_documentation_item(symbol_data, operation, result)
  if not symbol_data[operation] then
    symbol_data[operation] = {}
  end

  local content = result.contents
  -- jdtls puts documentation in a table where last element is content
  if type(content) == "table" and type(content[#content]) == "string" then
    content = content[#content]
  end
  -- Check for duplicates before adding documentation
  local is_duplicate = false
  for _, existing_item in ipairs(symbol_data[operation]) do
    if existing_item.code_block == content then
      is_duplicate = true
      break
    end
  end

  if not is_duplicate then
    table.insert(symbol_data[operation], { code_block = content })
  end
  return Utils.create_result("success", "documentation processed")
end

-- Process LSP results
function ResultProcessor.process_lsp_results(lsp_results, operation, symbol_data)
  local processed_count = 0

  for _, result in pairs(lsp_results) do
    -- Handle documentation specially
    if result.contents then
      local process_result = ResultProcessor.process_documentation_item(symbol_data, operation, result)
      if process_result.status == "success" then
        processed_count = processed_count + 1
      end
    -- Handle single item with range
    elseif result.range then
      local process_result = ResultProcessor.process_lsp_item(
        result.uri or result.targetUri,
        result.range,
        operation,
        symbol_data
      )
      if process_result.status == "success" then
        processed_count = processed_count + 1
      end
    -- Handle array of items
    else
      for _, item in pairs(result) do
        local process_result = ResultProcessor.process_lsp_item(
          item.uri or item.targetUri,
          item.range or item.targetSelectionRange,
          operation,
          symbol_data
        )
        if process_result.status == "success" and process_result.data ~= "Duplicate or enclosed entry" then
          processed_count = processed_count + 1
        end
      end
    end
  end

  return processed_count
end

-- Process code references from quickfix list
function ResultProcessor.process_quickfix_references(qflist, symbol_data)
  if not qflist or #qflist == 0 then
    return 0
  end

  log:debug("[ResultProcessor:process_quickfix_references] Processing %d quickfix items", #qflist)
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

      -- Extract code block using locals-enhanced treesitter
      local symbol_result = CodeExtractor.get_code_block_at_position(target_bufnr, row, col)

      if symbol_result.status == "success" then
        if not ResultProcessor.is_duplicate_or_enclosed(symbol_result.data, symbol_data) then
          -- Initialize references array if needed
          if not symbol_data["grep"] then
            symbol_data["grep"] = {}
          end
          table.insert(symbol_data["grep"], symbol_result.data)
          processed_count = processed_count + 1
        end
      end
    end
  end

  return processed_count
end

-----------------------
-- Main Tool Implementation
-----------------------

-- Process LSP symbols and collect results
local function process_lsp_symbols(symbols, state, symbolName)
  local results_count = 0

  for _, symbol in ipairs(symbols) do
    local filepath = symbol.file
    local line = symbol.range.start.line + 1 -- Convert to 1-indexed
    local col = symbol.range.start.character

    local success = Utils.open_file_and_set_cursor(filepath, line, col)
    if success then
      local current_bufnr = vim.api.nvim_get_current_buf()

      -- Call all LSP methods on this symbol
      for operation, method in pairs(CONSTANTS.LSP_METHODS) do
        local lsp_result = LspHandler.execute_request(current_bufnr, method)
        results_count = results_count
          + ResultProcessor.process_lsp_results(lsp_result, operation, state.symbol_data)
      end

      -- Save filetype for the output
      if results_count > 0 and not state.filetype then
        state.filetype = Utils.safe_get_filetype(current_bufnr)
      end
    end
  end

  return results_count
end

-- Process grep results and collect data
local function process_grep_results(grep_result, state, symbolName)
  local results_count = 0

  if not grep_result then
    return results_count
  end

  local success = Utils.open_file_and_set_cursor(grep_result.file, grep_result.line, grep_result.col)
  if success then
    local current_bufnr = vim.api.nvim_get_current_buf()

    -- Call all LSP methods on this symbol
    for operation, method in pairs(CONSTANTS.LSP_METHODS) do
      local lsp_result = LspHandler.execute_request(current_bufnr, method)
      results_count = results_count
        + ResultProcessor.process_lsp_results(lsp_result, operation, state.symbol_data)
    end

    -- Process quickfix list results
    if grep_result.qflist then
      results_count = results_count + ResultProcessor.process_quickfix_references(grep_result.qflist, state.symbol_data)
    end

    -- Save filetype if needed
    if results_count > 0 and not state.filetype then
      state.filetype = Utils.safe_get_filetype(current_bufnr)
    end
  end

  return results_count
end

-- Get file extension from context buffer
local function get_file_extension(context_bufnr)
  if not Utils.is_valid_buffer(context_bufnr) then
    return ""
  end

  local filename = Utils.safe_get_buffer_name(context_bufnr)
  return filename:match("%.([^%.]+)$") or "*"
end

-- Main command function
local function execute_main_command(self, args, input)
  local symbolName = args.symbolName
  local filePaths = args.filePaths
  local state = {
    symbol_data = {},
    filetype = "",
  }

  if not symbolName or symbolName == "" then
    return Utils.create_result("error", "Symbol name is required and cannot be empty.")
  end

  -- Save current state of view
  local context_winnr = self.chat.context.winnr
  local context_bufnr = self.chat.context.bufnr
  local chat_winnr = vim.api.nvim_get_current_win()

  -- Get file extension from context buffer if available
  local file_extension = get_file_extension(context_bufnr)

  -- Exit insert mode and switch focus to context window
  vim.cmd("stopinsert")
  vim.api.nvim_set_current_win(context_winnr)

  local results_count = 0

  local all_lsp_symbols = SymbolFinder.find_with_lsp(symbolName, filePaths)
  local grep_result = SymbolFinder.find_with_grep(symbolName, file_extension, filePaths)

  if all_lsp_symbols and #all_lsp_symbols > 0 then
    results_count = results_count + process_lsp_symbols(all_lsp_symbols, state, symbolName)
  end

  results_count = results_count + process_grep_results(grep_result, state, symbolName)

  -- Process all qflist results separately after LSP and grep processing
  local qflist = vim.fn.getqflist()
  results_count = results_count + ResultProcessor.process_quickfix_references(qflist, state.symbol_data)

  -- Handle case where we have no results
  if results_count == 0 then
    vim.api.nvim_set_current_win(chat_winnr)
    local filetype_msg = file_extension and (" in " .. file_extension .. " files") or ""
    return Utils.create_result(
      "error",
      "Symbol not found in workspace" .. filetype_msg .. ". Double check the spelling and tool usage instructions."
    )
  end

  -- Restore original state of view
  vim.api.nvim_set_current_buf(context_bufnr)
  vim.api.nvim_set_current_win(chat_winnr)

  -- Store state for output handler
  ListCodeUsagesTool.symbol_data = state.symbol_data
  ListCodeUsagesTool.filetype = state.filetype

  return Utils.create_result("success", "Tool executed successfully")
end

return {
  name = "list_code_usages",
  cmds = {
    function(self, args, input)
      return execute_main_command(self, args, input)
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
      local chat_message_content = string.format("Found usages of symbol: %s \n", symbol)

      for operation, code_blocks in pairs(ListCodeUsagesTool.symbol_data) do
        chat_message_content = chat_message_content .. string.format("\n%s: \n", operation, symbol)
        for _, code_block in ipairs(code_blocks) do
          if operation == "documentation" then
            chat_message_content = chat_message_content .. string.format("---\n%s\n", code_block.code_block)
          else
            chat_message_content = chat_message_content
              .. string.format(
                "---\nFilename: %s:%s-%s\n```%s\n%s\n```\n",
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
