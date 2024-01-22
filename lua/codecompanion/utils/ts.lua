local ts_utils = require("nvim-treesitter.ts_utils")

local M = {}

function M.goto_heading(direction)
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_row = cursor[1] - 1

  local query = [[
  (atx_heading) @heading
  ]]

  local heading_query = vim.treesitter.query.parse("markdown", query)

  for id, node in heading_query:iter_captures(ts_utils.get_root_for_position(current_row, 0), bufnr, current_row, -1) do
    if heading_query.captures[id] == "atx_heading" then
      local node_start_row, _, node_end_row, _ = node:range()

      if direction == "next" and node_start_row > current_row then
        ts_utils.goto_node(node, true)
        return
      elseif direction == "prev" and node_end_row < current_row then
        ts_utils.goto_node(ts_utils.get_previous_node(node, true), true)
        return
      end
    end
  end
end

return M
