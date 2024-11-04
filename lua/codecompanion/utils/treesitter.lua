local ts_parsers = require("nvim-treesitter.parsers")
local ts_utils = require("nvim-treesitter.ts_utils")
local api = vim.api

local M = {}

---@param direction string
---@param count integer
---@return nil
function M.goto_heading(direction, count)
  local bufnr = api.nvim_get_current_buf()
  local cursor = api.nvim_win_get_cursor(0)
  local current_row = cursor[1] - 1

  local parser = ts_parsers.get_parser(bufnr, "markdown")
  local root_tree = parser:parse()[1]:root()

  local query = vim.treesitter.query.parse("markdown", [[(atx_heading) @heading]])

  local from_row, to_row, found_headings
  if direction == "next" then
    from_row = current_row + 1
    to_row = -1 -- End of document
    found_headings = {}
    for id, node in query:iter_captures(root_tree, bufnr, from_row, to_row) do
      if query.captures[id] == "heading" then
        local node_start, _, _, _ = node:range()
        if node_start >= from_row then
          table.insert(found_headings, node) -- Collect valid headings in a table
          if #found_headings == count then -- Check if we have reached the desired count
            ts_utils.goto_node(found_headings[count], false, true)
            return
          end
        end
      end
    end
  elseif direction == "prev" then
    from_row = 0
    to_row = current_row
    found_headings = {}
    for id, node in query:iter_captures(root_tree, bufnr, from_row, to_row) do
      if query.captures[id] == "heading" then
        local _, _, node_end, _ = node:range()
        if node_end < current_row then
          table.insert(found_headings, node)
        end
      end
    end
    if #found_headings >= count then
      ts_utils.goto_node(found_headings[#found_headings - count + 1], false, true)
    end
  end

  -- If we haven't found the desired heading, we can stay at current position,
  -- or implement some behavior like wrapping around or signaling an error.
end

--- @param bufnr integer: The buffer number.
--- @param cursor integer[]: The cursor position as a {row, col} array.
--- @return string|nil: The function code as a string, or nil if no function is found.
function M.get_function_at_cursor(bufnr, cursor)
  local row, col = cursor[1] - 1, cursor[2]

  local parser = vim.treesitter.get_parser(bufnr)
  local tree = parser:parse()[1]
  local root = tree:root()

  local function_node = nil

  -- Traverse the tree to find the function node containing the cursor
  local function traverse(node)
    if node:type() == "function_definition" or node:type() == "function_declaration" then
      local start_row, start_col, end_row, end_col = node:range()
      if start_row <= row and end_row >= row and start_col <= col and end_col >= col then
        function_node = node
        return true
      end
    end

    for child in node:iter_children() do
      if traverse(child) then
        return true
      end
    end
    return false
  end

  traverse(root)

  if function_node then
    local start_row, start_col, end_row, end_col = function_node:range()
    local lines = api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
    lines[1] = lines[1]:sub(start_col + 1)
    lines[#lines] = lines[#lines]:sub(1, end_col)
    return table.concat(lines, "\n")
  else
    return ""
  end
end

return M
