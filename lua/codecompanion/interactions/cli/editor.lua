local api = vim.api
local fmt = string.format

local M = {}

local editor_winnr = nil ---@type number|nil
local selection = nil ---@type { path: string, start_line: number, end_line: number }|nil

---@param bufnr number
---@return boolean
local function is_file_buffer(bufnr)
  return vim.bo[bufnr].buftype == "" and api.nvim_buf_get_name(bufnr) ~= ""
end

---@param bufnr number
---@return string
local function get_relative_path(bufnr)
  local path = api.nvim_buf_get_name(bufnr)
  return vim.fs.relpath(vim.fn.getcwd(), path) or path
end

---@return nil
local function record_window()
  if is_file_buffer(api.nvim_get_current_buf()) then
    editor_winnr = api.nvim_get_current_win()
  end
end

---@return nil
local function record_selection()
  local bufnr = api.nvim_get_current_buf()
  if not is_file_buffer(bufnr) then
    return
  end

  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  if start_line == 0 then
    return
  end

  selection = { path = get_relative_path(bufnr), start_line = start_line, end_line = end_line }
end

---Follow the window the user edits code in, and what they select there
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
  api.nvim_create_autocmd("ModeChanged", {
    group = group,
    pattern = "[vV\x16]*:*",
    callback = function()
      -- The `'<` and `'>` marks are only set once visual mode has ended
      vim.schedule(record_selection)
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

---Describe the user's editor for an agent, sharing a selection only with the first prompt after it was made
---@return string
function M.describe()
  local lines = {}

  local winnr = get_code_window()
  if winnr then
    local bufnr = api.nvim_win_get_buf(winnr)
    local cursor = api.nvim_win_get_cursor(winnr)
    table.insert(lines, fmt("- Current file: %s, cursor on line %d", get_relative_path(bufnr), cursor[1]))
  end

  if selection then
    table.insert(lines, fmt("- Selected: %s, lines %d-%d", selection.path, selection.start_line, selection.end_line))
    selection = nil
  end

  if #lines == 0 then
    return ""
  end

  table.insert(lines, 1, "The user's Neovim editor as they sent this prompt. Use it only if the prompt refers to it:")
  return table.concat(lines, "\n")
end

---Find a file reference, such as `lua/init.lua:42` or `lua/init.lua#L42`, around a column in a line of text
---@param opts { line: string, col: number }
---@return { path: string, line_number?: number }|nil
function M.find_reference(opts)
  local init = 1

  while true do
    local start_col, end_col = opts.line:find("[%w%._%-/~]+", init)
    if not start_col then
      return nil
    end

    local rest = opts.line:sub(end_col + 1)
    local suffix = rest:match("^:%d+") or rest:match("^#L%d+") or ""

    if opts.col >= start_col and opts.col <= end_col + #suffix then
      local path = opts.line:sub(start_col, end_col):gsub("%.+$", "")
      return { path = path, line_number = tonumber(suffix:match("%d+")) }
    end

    init = end_col + #suffix + 1
  end
end

---Open a file in the window the user edits code in, rather than in place of the agent
---@param opts { path: string, line_number?: number, from_winnr: number }
---@return nil
function M.open_file(opts)
  local winnr = get_code_window()
  if not winnr or winnr == opts.from_winnr then
    vim.cmd.split()
    winnr = api.nvim_get_current_win()
  end

  api.nvim_set_current_win(winnr)
  vim.cmd.edit(vim.fn.fnameescape(vim.fs.normalize(opts.path)))

  if opts.line_number then
    local last_line = api.nvim_buf_line_count(0)
    api.nvim_win_set_cursor(winnr, { math.min(opts.line_number, last_line), 0 })
    vim.cmd("normal! zz")
  end
end

return M
