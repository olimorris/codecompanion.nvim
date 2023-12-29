local M = {}

---@param winid? number
M.scroll_to_end = function(winid)
  winid = winid or 0
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local lnum = vim.api.nvim_buf_line_count(bufnr)
  local last_line = vim.api.nvim_buf_get_lines(bufnr, -2, -1, true)[1]
  vim.api.nvim_win_set_cursor(winid, { lnum, vim.api.nvim_strwidth(last_line) })
end

---@param bufnr nil|integer
M.buf_scroll_to_end = function(bufnr)
  for _, winid in ipairs(M.buf_list_wins(bufnr or 0)) do
    M.scroll_to_end(winid)
  end
end

---@param bufnr nil|integer
---@return integer[]
M.buf_list_wins = function(bufnr)
  local ret = {}
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
      table.insert(ret, winid)
    end
  end
  return ret
end

M._noop = function() end

---@param name string
M.set_dot_repeat = function(name)
  vim.go.operatorfunc = "v:lua.require'openai.utils.util'._noop"
  vim.cmd.normal({ args = { "g@l" }, bang = true })
  vim.go.operatorfunc = string.format("v:lua.require'openai'.%s", name)
end

---@param bufnr nil|integer
M.get_language = function(bufnr)
  bufnr = bufnr or 0
  local ft = vim.api.nvim_buf_get_option(bufnr, "filetype")

  if ft == "cpp" then
    return "C++"
  end

  return ft
end
return M
