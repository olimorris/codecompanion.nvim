local CodeExtractor = require("codecompanion.strategies.chat.tools.catalog.list_code_usages.code_extractor")
local Utils = require("codecompanion.strategies.chat.tools.catalog.list_code_usages.utils")
local log = require("codecompanion.utils.log")

---@class ListCodeUsages.ResultProcessor
local ResultProcessor = {}

--- Checks if a new code block is a duplicate or enclosed by existing blocks
---
--- This function prevents redundant code blocks from being added to the results
--- by checking if the new block is identical to or completely contained within
--- any existing block across all operation types.
---
---@param new_block table Code block with filename, start_line, end_line fields
---@param symbol_data table Existing symbol data organized by operation type
---@return boolean True if the block is a duplicate or enclosed by an existing block
function ResultProcessor.is_duplicate_or_enclosed(new_block, symbol_data)
  for _, blocks in pairs(symbol_data) do
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

--- Processes a single LSP result item and extracts its code block
---
--- This function takes an LSP result item (with URI and range) and extracts
--- the corresponding code block using the CodeExtractor. It handles deduplication
--- and adds the result to the appropriate operation category.
---
---@param uri string The file URI from the LSP result
---@param range table LSP range object with start/end positions
---@param operation string The type of LSP operation (e.g., "references", "definition")
---@param symbol_data table Symbol data storage organized by operation type
---@return table Result object indicating success or failure
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

--- Processes documentation items from LSP hover responses
---
--- This function handles the special case of documentation/hover results,
--- which contain text content rather than code locations. It extracts the
--- documentation content and adds it to the results with deduplication.
---
---@param symbol_data table Symbol data storage organized by operation type
---@param operation string The operation type (typically "documentation")
---@param result table LSP hover result containing documentation content
---@return table Result object indicating success or failure
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

--- Processes LSP results from multiple clients for a specific operation
---
--- This function handles the complex task of processing LSP results that can come
--- in various formats (single items, arrays, documentation) from multiple LSP clients.
--- It delegates to appropriate processing functions based on the result structure.
---
---@param lsp_results table Results from LSP clients, organized by client name
---@param operation string The LSP operation type (e.g., "references", "definition")
---@param symbol_data table Symbol data storage organized by operation type
---@return number Count of successfully processed results
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
      local process_result =
        ResultProcessor.process_lsp_item(result.uri or result.targetUri, result.range, operation, symbol_data)
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

--- Processes code references from the quickfix list (grep results)
---
--- This function processes grep search results stored in Neovim's quickfix list.
--- It extracts code blocks for each match and adds them to the symbol data with
--- proper deduplication. This provides broader coverage when LSP doesn't find
--- all symbol occurrences.
---
---@param qflist table Array of quickfix items from vim.fn.getqflist()
---@param symbol_data table Symbol data storage organized by operation type
---@return number Count of successfully processed quickfix items
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

return ResultProcessor
