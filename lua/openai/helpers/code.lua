local M = {}

---@param start_line integer
---@param end_line integer
function M.get_code(start_line, end_line)
  local lines = {}
  for line_num = start_line, end_line do
    local line = string.format("%d: %s", line_num, vim.fn.getline(line_num))
    table.insert(lines, line)
  end

  return table.concat(lines, "\n")
end

return M
