local M = {}

local ESC_FEEDKEY = vim.api.nvim_replace_termcodes("<ESC>", true, false, true)

---@param table table
M.count = function(table)
  local count = 0
  for _ in pairs(table) do
    count = count + 1
  end

  return count
end

---@param table table
---@param value string
M.contains = function(table, value)
  for _, v in pairs(table) do
    if v == value then
      return true
    end
  end
  return false
end

M._noop = function() end

---@param name string
M.set_dot_repeat = function(name)
  vim.go.operatorfunc = "v:lua.require'codecompanion.utils.util'._noop"
  vim.cmd.normal({ args = { "g@l" }, bang = true })
  vim.go.operatorfunc = string.format("v:lua.require'codecompanion'.%s", name)
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

local function is_visual_mode(mode)
  return mode == "v" or mode == "V" or mode == "^V"
end

local function is_normal_mode(mode)
  return mode == "n" or mode == "no" or mode == "nov" or mode == "noV" or mode == "no"
end

---@param bufnr nil|integer
function M.get_visual_selection(bufnr)
  bufnr = bufnr or 0

  vim.api.nvim_feedkeys(ESC_FEEDKEY, "n", true)
  vim.api.nvim_feedkeys("gv", "x", false)
  vim.api.nvim_feedkeys(ESC_FEEDKEY, "n", true)

  local start_line, start_col = unpack(vim.api.nvim_buf_get_mark(bufnr, "<"))
  local end_line, end_col = unpack(vim.api.nvim_buf_get_mark(bufnr, ">"))

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)

  -- get whole buffer if there is no current/previous visual selection
  if start_line == 0 then
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
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
---@param bufnr nil|integer
---@return table
function M.get_context(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local mode = vim.fn.mode()
  local cursor_pos = vim.api.nvim_win_get_cursor(vim.api.nvim_get_current_win())

  local lines, start_line, start_col, end_line, end_col = {}, cursor_pos[1], cursor_pos[2], cursor_pos[1], cursor_pos[2]

  if is_visual_mode(mode) then
    lines, start_line, start_col, end_line, end_col = M.get_visual_selection(bufnr)
  end

  return {
    bufnr = bufnr,
    mode = mode,
    is_visual = is_visual_mode(mode),
    is_normal = is_normal_mode(mode),
    buftype = vim.api.nvim_buf_get_option(bufnr, "buftype") or "",
    filetype = M.get_filetype(bufnr),
    cursor_pos = cursor_pos,
    lines = lines,
    start_line = start_line,
    start_col = start_col,
    end_line = end_line,
    end_col = end_col,
  }
end

---@param msg string
---@param vars table
---@param mapping table
---@return string
function M.replace_vars(msg, vars, mapping)
  local replacements = {}
  for _, var_name in ipairs(vars) do
    -- Check if the variable exists in the mapping
    if mapping[var_name] then
      table.insert(replacements, mapping[var_name])
    else
      error("Variable '" .. var_name .. "' not found in the mapping.")
    end
  end
  return string.format(msg, unpack(replacements))
end

return M
