local api = vim.api

local M = {}

local ESC_FEEDKEY = api.nvim_replace_termcodes("<ESC>", true, false, true)

---@param bufnr nil|integer
---@return string
M.get_filetype = function(bufnr)
  bufnr = bufnr or 0
  local ft = api.nvim_buf_get_option(bufnr, "filetype")

  if ft == "cpp" then
    return "C++"
  end

  return ft
end

---@param mode string
---@return boolean
local function is_visual_mode(mode)
  return mode == "v" or mode == "V" or mode == "^V"
end

---@param mode string
---@return boolean
local function is_normal_mode(mode)
  return mode == "n" or mode == "no" or mode == "nov" or mode == "noV" or mode == "no"
end

---@param bufnr nil|integer
---@return table,number,number,number,number
function M.get_visual_selection(bufnr)
  bufnr = bufnr or 0

  api.nvim_feedkeys(ESC_FEEDKEY, "n", true)
  api.nvim_feedkeys("gv", "x", false)
  api.nvim_feedkeys(ESC_FEEDKEY, "n", true)

  local end_line, end_col = unpack(api.nvim_buf_get_mark(bufnr, ">"))
  local start_line, start_col = unpack(api.nvim_buf_get_mark(bufnr, "<"))
  local lines = api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)

  -- get whole buffer if there is no current/previous visual selection
  if start_line == 0 then
    lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
    start_line = 1
    start_col = 0
    end_line = #lines
    end_col = #lines[#lines]
  end

  -- use 1-based indexing and handle selections made in visual line mode (see :help getpos)
  start_col = start_col + 1
  end_col = math.min(end_col, #lines[#lines] - 1) + 1

  -- shorten first/last line according to start_col/end_col
  lines[#lines] = lines[#lines]:sub(1, end_col)
  lines[1] = lines[1]:sub(start_col)

  return lines, start_line, start_col, end_line, end_col
end

---Get the context of the current buffer.
---@param bufnr? integer
---@param args? table
---@return table
function M.get(bufnr, args)
  bufnr = bufnr or api.nvim_get_current_buf()
  local winnr = api.nvim_get_current_win()
  local mode = vim.fn.mode()
  local cursor_pos = api.nvim_win_get_cursor(winnr)

  local lines, start_line, start_col, end_line, end_col = {}, cursor_pos[1], cursor_pos[2], cursor_pos[1], cursor_pos[2]

  local is_visual = false
  local is_normal = true

  if args and args.range and args.range > 0 then
    is_visual = true
    is_normal = false
    mode = "v"
    lines, start_line, start_col, end_line, end_col = M.get_visual_selection(bufnr)
  elseif is_visual_mode(mode) then
    is_visual = true
    is_normal = false
    lines, start_line, start_col, end_line, end_col = M.get_visual_selection(bufnr)
  end

  -- Consider adjustment here for is_normal if there are scenarios where it doesn't align appropriately

  return {
    winnr = winnr,
    bufnr = bufnr,
    mode = mode,
    is_visual = is_visual,
    is_normal = is_normal,
    buftype = api.nvim_buf_get_option(bufnr, "buftype") or "",
    filetype = M.get_filetype(bufnr),
    filename = api.nvim_buf_get_name(bufnr),
    cursor_pos = cursor_pos,
    lines = lines,
    start_line = start_line,
    start_col = start_col,
    end_line = end_line,
    end_col = end_col,
  }
end

return M
