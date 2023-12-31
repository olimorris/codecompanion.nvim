local M = {}

local ESC_FEEDKEY = vim.api.nvim_replace_termcodes("<ESC>", true, false, true)

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
M.get_filetype = function(bufnr)
  bufnr = bufnr or 0
  local ft = vim.api.nvim_buf_get_option(bufnr, "filetype")

  if ft == "cpp" then
    return "C++"
  end

  return ft
end

---@param bufnr nil|integer
function M.get_visual_selection(bufnr)
  bufnr = bufnr or 0

  vim.api.nvim_feedkeys(ESC_FEEDKEY, "n", true)
  vim.api.nvim_feedkeys("gv", "x", false)
  vim.api.nvim_feedkeys(ESC_FEEDKEY, "n", true)

  local start_row, start_col = unpack(vim.api.nvim_buf_get_mark(bufnr, "<"))
  local end_row, end_col = unpack(vim.api.nvim_buf_get_mark(bufnr, ">"))
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row - 1, end_row, false)

  -- get whole buffer if there is no current/previous visual selection
  if start_row == 0 then
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    start_row = 1
    start_col = 0
    end_row = #lines
    end_col = #lines[#lines]
  end

  -- use 1-based indexing and handle selections made in visual line mode (see :help getpos)
  start_col = start_col + 1
  end_col = math.min(end_col, #lines[#lines] - 1) + 1

  -- shorten first/last line according to start_col/end_col
  lines[#lines] = lines[#lines]:sub(1, end_col)
  lines[1] = lines[1]:sub(start_col)

  return lines, start_row, start_col, end_row, end_col
end

---Get the context of the current buffer.
---@param bufnr nil|integer
---@return table
function M.get_context(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local lines, start_row, start_col, end_row, end_col = M.get_visual_selection(bufnr)

  return {
    bufnr = bufnr,
    mode = vim.fn.mode(),
    buftype = vim.api.nvim_buf_get_option(bufnr, "buftype") or "",
    filetype = M.get_filetype(bufnr),
    lines = lines,
    start_row = start_row,
    start_col = start_col,
    end_row = end_row,
    end_col = end_col,
  }
end

return M
