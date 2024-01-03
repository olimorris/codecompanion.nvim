local M = {}

---@param start_line integer
---@param end_line integer
---@param opts table|nil
function M.get_code(start_line, end_line, opts)
  local lines = {}
  for line_num = start_line, end_line do
    local line
    if opts and opts.show_line_numbers then
      line = string.format("%d: %s", line_num, vim.fn.getline(line_num))
    else
      line = string.format("%s", vim.fn.getline(line_num))
    end
    table.insert(lines, line)
  end

  return table.concat(lines, "\n")
end

return M
