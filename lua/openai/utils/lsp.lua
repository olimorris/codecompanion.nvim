--Taken from the excellent plugin: https://github.com/piersolenski/wtf.nvim

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

---@param start_line integer
---@param end_line integer
function M.get_diagnostics(start_line, end_line)
  if end_line == nil then
    end_line = start_line
  end

  -- local bufnr = vim.api.nvim_win_get_buf(0)
  local bufnr = vim.api.nvim_get_current_buf()

  local diagnostics = {}

  for line_num = start_line, end_line do
    local line_diagnostics = vim.diagnostic.get(bufnr, {
      lnum = line_num - 1,
      severity = { min = vim.diagnostic.severity.HINT },
    })

    if next(line_diagnostics) ~= nil then
      for _, diagnostic in ipairs(line_diagnostics) do
        table.insert(diagnostics, {
          line_number = line_num,
          message = diagnostic.message,
          severity = vim.diagnostic.severity[diagnostic.severity],
        })
      end
    end
  end

  return diagnostics
end

return M
