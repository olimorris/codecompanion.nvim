local Utils = require("codecompanion.strategies.chat.agents.tools.list_code_usages.utils")
local log = require("codecompanion.utils.log")

---@class ListCodeUsages.CodeExtractor
local CodeExtractor = {}

local CONSTANTS = {
  MAX_BLOCK_SCAN_LINES = 100,
}

--- Finds the most appropriate code block using TreeSitter and locals queries
---
--- This function uses TreeSitter to find the most contextually relevant code block
--- around a given position. It leverages locals queries to find scopes and attempts
--- to return the smallest significant scope that contains the target position.
---
---@param bufnr number The buffer number to extract from
---@param row number The row position (0-indexed)
---@param col number The column position (0-indexed)
---@return userdata|nil TreeSitter node representing the best code block, or nil if not found
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
        "module",
        "namespace",
        "class",
        "interface",
        "struct",
        "impl",
        "enum",
        "constructor",
        "function",
        "expression_statement",
        "method",
        "procedure",
        "def",
        "type",
        "const",
        "field",
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

--- Extracts code text and metadata from a TreeSitter node
---
--- This function converts a TreeSitter node into a structured data object
--- containing the code text, line numbers, filename, and filetype information
--- needed for display in the tool output.
---
---@param bufnr number The buffer number containing the node
---@param node userdata TreeSitter node to extract data from
---@return table Result object with status and extracted code data
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

--- Fallback code extraction using indentation-based heuristics
---
--- When TreeSitter is not available or doesn't provide useful results, this function
--- uses indentation patterns to determine code block boundaries. It scans upward and
--- downward from the target position to find lines with consistent indentation.
---
---@param bufnr number The buffer number to extract from
---@param row number The row position (0-indexed)
---@param col number The column position (0-indexed)
---@return table Result object with status and extracted code data
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

--- Main entry point for extracting code blocks at a specific position
---
--- This function orchestrates the code extraction process by first attempting
--- TreeSitter-based extraction and falling back to indentation-based extraction
--- if TreeSitter is not available or doesn't provide useful results.
---
---@param bufnr number The buffer number to extract from
---@param row number The row position (0-indexed)
---@param col number The column position (0-indexed)
---@return table Result object with status and extracted code data
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

return CodeExtractor
