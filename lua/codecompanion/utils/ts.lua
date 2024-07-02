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

return M
