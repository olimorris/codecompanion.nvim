local files = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

local api = vim.api

local M = {}

local MAX_WRAPPED_LINES = 2

local editor_winnr = nil ---@type number|nil

---@param bufnr number
---@return boolean
local function is_file_buffer(bufnr)
  return vim.bo[bufnr].buftype == "" and api.nvim_buf_get_name(bufnr) ~= ""
end

---@return nil
local function record_window()
  if is_file_buffer(api.nvim_get_current_buf()) then
    editor_winnr = api.nvim_get_current_win()
  end
end

---Follow the window the user edits code in
---@return nil
function M.track()
  record_window()

  local group = api.nvim_create_augroup("codecompanion.cli.editor", { clear = true })
  api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = group,
    callback = function()
      -- A new split shows the user's file until the agent's buffer replaces it, so wait for that
      vim.schedule(record_window)
    end,
  })
end

---The window the user last edited code in, or another showing a file if the agent has since taken it over
---@return number|nil
local function get_code_window()
  if editor_winnr and api.nvim_win_is_valid(editor_winnr) and is_file_buffer(api.nvim_win_get_buf(editor_winnr)) then
    return editor_winnr
  end

  for _, winnr in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_config(winnr).relative == "" and is_file_buffer(api.nvim_win_get_buf(winnr)) then
      return winnr
    end
  end
  return nil
end

-- Bytes from 128 up are the parts of non-ASCII characters, which are valid in a filename
local PATH_CHARS = "[%w%._%-/\\~\128-\255]"

---Split a line number such as `:42` or `#L42` from the end of a path
---@param text string
---@return { path: string, line_number?: number }
local function split_line_number(text)
  local path, line_number = text:match("^(.-):(%d+)$")
  if not path then
    path, line_number = text:match("^(.-)#L(%d+)$")
  end
  return { path = path or text, line_number = tonumber(line_number) }
end

---A path in backticks or double quotes, which may hold spaces that an unquoted path can't
---@param opts { line: string, col: number }
---@return { path: string, line_number?: number }|nil
local function find_quoted_reference(opts)
  for start_col, text, end_col in opts.line:gmatch('()[`"]([^`"]+)[`"]()') do
    if opts.col >= start_col and opts.col < end_col and text:find("[/\\.]") then
      return split_line_number(vim.trim(text))
    end
  end
end

---The span of the next unquoted path, including a Windows drive such as `C:\`
---@param opts { line: string, init: number }
---@return { start_col: number, end_col: number }|nil
local function find_path_span(opts)
  local start_col, end_col = opts.line:find(PATH_CHARS .. "+", opts.init)
  if not start_col then
    return nil
  end

  local drive_start, drive_end = opts.line:find("^%a:[\\/]" .. PATH_CHARS .. "*", start_col)
  if drive_start then
    return { start_col = drive_start, end_col = drive_end }
  end
  return { start_col = start_col, end_col = end_col }
end

---@param opts { line: string, col: number }
---@return { path: string, line_number?: number }|nil
local function find_unquoted_reference(opts)
  local init = 1
  while true do
    local span = find_path_span({ line = opts.line, init = init })
    if not span then
      return nil
    end

    local rest = opts.line:sub(span.end_col + 1)
    local suffix = rest:match("^:%d+") or rest:match("^#L%d+") or ""

    if opts.col >= span.start_col and opts.col <= span.end_col + #suffix then
      local path = opts.line:sub(span.start_col, span.end_col):gsub("%.+$", "")
      return { path = path, line_number = tonumber(suffix:match("%d+")) }
    end

    init = span.end_col + #suffix + 1
  end
end

---@param reference? { path: string }
---@return boolean
local function is_existing_file(reference)
  return reference ~= nil and files.exists(vim.fs.normalize(reference.path))
end

---Find a file reference, such as `lua/init.lua:42` or `lua/init.lua#L42`, around a column in a line of text
---@param opts { line: string, col: number }
---@return { path: string, line_number?: number }|nil
function M.find_reference(opts)
  local quoted = find_quoted_reference(opts)
  if is_existing_file(quoted) then
    return quoted
  end

  -- A quoted span can be a whole command, such as `git diff lua/init.lua`, so try the path under the cursor in it
  local unquoted = find_unquoted_reference(opts)
  if is_existing_file(unquoted) then
    return unquoted
  end
  return quoted or unquoted
end

---Join lines of the agent's output, without the indentation it adds when it wraps a long line
---@param opts { lines: string[], first: number, last: number, row: number, col: number }
---@return { text: string, col: number }
local function join_lines(opts)
  local parts = {}
  local col = opts.col
  local offset = 0

  for row = opts.first, opts.last do
    local line = opts.lines[row]
    local indent = #line:match("^%s*")
    local part = vim.trim(line)
    if row == opts.row then
      col = offset + opts.col - indent
    end
    table.insert(parts, part)
    offset = offset + #part
  end

  return { text = table.concat(parts), col = col }
end

---Find the file reference under the cursor in a buffer, rejoining a path the agent wrapped across lines
---@param opts { bufnr: number, row: number, col: number }
---@return { path: string, line_number?: number }|nil
function M.find_reference_at(opts)
  local first = math.max(1, opts.row - MAX_WRAPPED_LINES)
  local lines = api.nvim_buf_get_lines(opts.bufnr, first - 1, opts.row + MAX_WRAPPED_LINES, false)
  local row = opts.row - first + 1

  -- Claude Code wraps a long path with nothing marking a continued line, so trust the smallest join that names a real file
  for extra_lines = 0, MAX_WRAPPED_LINES * 2 do
    for above = 0, extra_lines do
      local below = extra_lines - above
      if above <= MAX_WRAPPED_LINES and below <= MAX_WRAPPED_LINES and row - above >= 1 and row + below <= #lines then
        local joined = join_lines({ lines = lines, first = row - above, last = row + below, row = row, col = opts.col })
        local reference = M.find_reference({ line = joined.text, col = joined.col })
        if is_existing_file(reference) then
          return reference
        end
      end
    end
  end

  return M.find_reference({ line = lines[row], col = opts.col })
end

---Can a file open in this window without disturbing the agent or a sidebar such as a file tree?
---@param opts { winnr: number, from_winnr: number }
---@return boolean
local function is_editable_window(opts)
  if opts.winnr == opts.from_winnr or api.nvim_win_get_config(opts.winnr).relative ~= "" then
    return false
  end
  local buftype = vim.bo[api.nvim_win_get_buf(opts.winnr)].buftype
  return buftype == "" or buftype == "acwrite"
end

---Pick one of the user's own windows to open a file in, preferring the one they were last coding in
---@param opts { from_winnr: number }
---@return number|nil
local function get_target_window(opts)
  local code_winnr = get_code_window()
  local tabpage = api.nvim_get_current_tabpage()
  if
    code_winnr
    and api.nvim_win_get_tabpage(code_winnr) == tabpage
    and is_editable_window({ winnr = code_winnr, from_winnr = opts.from_winnr })
  then
    return code_winnr
  end

  local previous_winnr = vim.fn.win_getid(vim.fn.winnr("#"))
  if previous_winnr ~= 0 and is_editable_window({ winnr = previous_winnr, from_winnr = opts.from_winnr }) then
    return previous_winnr
  end

  for _, winnr in ipairs(api.nvim_tabpage_list_wins(tabpage)) do
    if is_editable_window({ winnr = winnr, from_winnr = opts.from_winnr }) then
      return winnr
    end
  end
end

---Open a file in one of the user's own windows, rather than in place of the agent
---@param opts { path: string, line_number?: number, from_winnr: number }
---@return nil
function M.open_file(opts)
  local winnr = get_target_window(opts)
  if not winnr then
    -- Only the agent and sidebars are open, so make room beside the agent instead of beneath it
    vim.cmd("leftabove vsplit")
    winnr = api.nvim_get_current_win()
  end

  api.nvim_set_current_win(winnr)
  local ok, err = pcall(vim.cmd.edit, vim.fn.fnameescape(vim.fs.normalize(opts.path)))
  if not ok then
    log:error("[CLI] Could not open %s: %s", opts.path, err)
    return nil
  end

  if opts.line_number then
    local last_line = api.nvim_buf_line_count(0)
    api.nvim_win_set_cursor(winnr, { math.min(opts.line_number, last_line), 0 })
    vim.cmd("normal! zz")
  end
end

return M
