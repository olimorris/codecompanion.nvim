local M = {}

---Taken from the excellent plugin: https://github.com/piersolenski/wtf.nvim
---@param start_line integer
---@param end_line integer
---@param bufnr integer|nil
function M.get_diagnostics(start_line, end_line, bufnr)
  if end_line == nil then
    end_line = start_line
  end

  bufnr = bufnr or vim.api.nvim_get_current_buf()

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
