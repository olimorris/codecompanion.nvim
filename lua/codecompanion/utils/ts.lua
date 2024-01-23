local ts_utils = require("nvim-treesitter.ts_utils")
local ts_parsers = require("nvim-treesitter.parsers")

local M = {}

function M.goto_heading(direction)
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_row = cursor[1] - 1

  local parser = ts_parsers.get_parser(bufnr, "markdown")
  local root_tree = parser:parse()[1]:root()

  local query = vim.treesitter.query.parse("markdown", [[(atx_heading) @heading]])

  local from_row, to_row, last_heading
  if direction == "next" then
    from_row = current_row + 1
    to_row = -1 -- End of document
    for id, node in query:iter_captures(root_tree, bufnr, from_row, to_row) do
      if query.captures[id] == "heading" then
        local node_start, _, _, _ = node:range()
        if node_start >= from_row then
          ts_utils.goto_node(node, false, true)
          return
        end
      end
    end
  elseif direction == "prev" then
    from_row = 0
    to_row = current_row
    for id, node in query:iter_captures(root_tree, bufnr, from_row, to_row) do
      if query.captures[id] == "heading" then
        local _, _, node_end, _ = node:range()
        last_heading = node
        if node_end >= current_row then
          break
        end
      end
    end
    if last_heading then
      ts_utils.goto_node(last_heading, false, true)
    end
  end
end

return M
