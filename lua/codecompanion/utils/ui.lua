local log = require("codecompanion.utils.log")

local api = vim.api

local M = {}

---Open a floating window with the provided lines
---@param lines table
---@param opts table
---@return number,number The buffer and window numbers
M.create_float = function(lines, opts)
  local window = opts.window
  local optsWidth = opts.window.width == "auto" and 0.45 or opts.window.width
  local width = optsWidth > 1 and optsWidth or opts.width or 85
  local height = window.height > 1 and window.height or opts.height or 17

  local bufnr = opts.bufnr or api.nvim_create_buf(false, true)

  require("codecompanion.utils").set_option(bufnr, "filetype", opts.filetype or "codecompanion")
  -- Calculate center position if not specified
  local row = opts.row or window.row or 10
  local col = opts.col or window.col or 0
  if row == "center" then
    row = math.floor((vim.o.lines - height) / 2)
  end
  if col == "center" then
    col = math.floor((vim.o.columns - width) / 2)
  end

  local winnr = api.nvim_open_win(bufnr, true, {
    relative = opts.relative or "cursor",
    -- thanks to @mini.nvim for this, it's for >= 0.11, to respect users winborder style
    border = (vim.fn.exists("+winborder") == 1 and vim.o.winborder ~= "") and vim.o.winborder or "single",
    width = width,
    height = height,
    style = "minimal",
    row = row,
    col = col,
    title = opts.title or "Options",
    title_pos = "center",
  })

  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  if opts.lock then
    vim.bo[bufnr].modified = false
    vim.bo[bufnr].modifiable = false
  end

  if opts.opts then
    M.set_win_options(winnr, opts.opts)
  end

  if opts.ignore_keymaps then
    return bufnr, winnr
  end

  local function close()
    api.nvim_buf_delete(bufnr, { force = true })
  end

  vim.keymap.set("n", "q", close, { buffer = bufnr })
  vim.keymap.set("n", "<ESC>", close, { buffer = bufnr })

  return bufnr, winnr
end

---@param bufnr number
---@param ns_id number
---@param message string
---@param opts? table
---@return nil
M.set_virtual_text = function(bufnr, ns_id, message, opts)
  local defaults = {
    hl_group = "CodeCompanionVirtualText",
    virt_text_pos = "eol",
  }

  opts = vim.tbl_deep_extend("force", {}, defaults, opts or {})

  api.nvim_buf_set_extmark(bufnr, ns_id, api.nvim_buf_line_count(bufnr) - 1, 0, {
    virt_text = { { message, opts.hl_group } },
    virt_text_pos = opts.virt_text_pos,
  })
end

---Show a notification with virtual lines in a buffer
---@param bufnr number The buffer number to display the notification in
---@param opts table Options for the notification
---@return number The extmark ID
function M.show_buffer_notification(bufnr, opts)
  opts = opts or {}

  local ns_id = api.nvim_create_namespace(opts.namespace or ("codecompanion_notification_" .. tostring(bufnr)))
  local buf_lines = api.nvim_buf_line_count(bufnr)
  local win_lines = vim.o.lines - vim.o.cmdheight
  local target_line = opts.line or (buf_lines - 1)

  local main_text = opts.text or "Notification"
  local main_hl = opts.main_hl or "CodeCompanionChatWarn"
  local sub_text = opts.sub_text
  local sub_hl = opts.sub_hl or "CodeCompanionChatSubtext"

  local required_lines = 0
  local virt_lines = {}

  local function increment(line_count)
    line_count = line_count or 1
    required_lines = required_lines + line_count
  end
  local function spacer()
    increment()
    table.insert(virt_lines, { { "", "Normal" } })
  end

  if opts.spacer then
    spacer()
  end

  -- Create the main text line
  increment(2)
  table.insert(virt_lines, {
    { "", "Normal" },
    { main_text, main_hl },
  })

  -- Add sub-text if provided
  if sub_text then
    increment(2)
    table.insert(virt_lines, {
      { "╰─ ", "Comment" },
      { sub_text, sub_hl },
    })
  end

  if opts.footer then
    spacer()
  end

  -- Show the notification above the bottom line if we're out of space
  local show_above = opts.above or false
  if win_lines <= (buf_lines + required_lines) then
    show_above = true
  end

  return api.nvim_buf_set_extmark(bufnr, ns_id, target_line, 0, {
    virt_lines = virt_lines,
    virt_lines_above = show_above,
    priority = opts.priority or ((vim.hl or vim.highlight).priorities.user + 10),
  })
end

---Clear a notification via the namespace
---@param bufnr number The buffer number
---@param opts? table Options for clearing the notification
function M.clear_notification(bufnr, opts)
  opts = opts or {}
  local ns_id = api.nvim_create_namespace(opts.namespace or ("codecompanion_notification_" .. tostring(bufnr)))
  pcall(api.nvim_buf_clear_namespace, bufnr, ns_id, opts.line_start or 0, opts.line_end or -1)
end

---@param bufnr number
---@return boolean
M.buf_is_empty = function(bufnr)
  return api.nvim_buf_line_count(bufnr) == 1 and api.nvim_buf_get_lines(bufnr, 0, -1, false)[1] == ""
end

---@param bufnr number
---@return boolean
M.buf_is_active = function(bufnr)
  return api.nvim_get_current_buf() == bufnr
end

---@param bufnr nil|integer
---@return integer[]
M.buf_list_wins = function(bufnr)
  local wins = {}

  if not bufnr or bufnr == 0 then
    bufnr = api.nvim_get_current_buf()
  end

  for _, winnr in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_is_valid(winnr) and api.nvim_win_get_buf(winnr) == bufnr then
      table.insert(wins, winnr)
    end
  end

  return wins
end

---@param winnr? number
---@return nil
M.scroll_to_end = function(winnr)
  winnr = winnr or 0
  local bufnr = api.nvim_win_get_buf(winnr)
  local lnum = api.nvim_buf_line_count(bufnr)
  local last_line = api.nvim_buf_get_lines(bufnr, -2, -1, true)[1]
  api.nvim_win_set_cursor(winnr, { lnum, api.nvim_strwidth(last_line) })
end

---@param bufnr nil|integer
---@return nil
M.buf_scroll_to_end = function(bufnr)
  for _, winnr in ipairs(M.buf_list_wins(bufnr or 0)) do
    M.scroll_to_end(winnr)
  end
end

---Scroll the window to show a specific line without moving cursor
---@param bufnr number The buffer number
---@param line_num number The line number to scroll to (1-based)
function M.scroll_to_line(bufnr, line_num)
  local winnr = M.buf_get_win(bufnr)
  if not winnr then
    return
  end

  api.nvim_win_call(winnr, function()
    vim.cmd(":" .. tostring(line_num))
    vim.cmd("normal! zz")
  end)
end

---Scroll to line and briefly highlight the edit area
---@param bufnr number The buffer number
---@param line_num number The line number to scroll to
---@param num_lines? number Number of lines that were changed
function M.scroll_and_highlight(bufnr, line_num, num_lines)
  num_lines = num_lines or 1

  M.scroll_to_line(bufnr, line_num)

  local ns_id = api.nvim_create_namespace("codecompanion_edit_highlight")

  -- Highlight the edited lines
  for i = 0, num_lines - 1 do
    local highlight_line = line_num + i - 1 -- Convert to 0-based
    if highlight_line >= 0 and highlight_line < api.nvim_buf_line_count(bufnr) then
      api.nvim_buf_add_highlight(bufnr, ns_id, "DiffAdd", highlight_line, 0, -1)
    end
  end

  -- Clear highlight after a short delay
  vim.defer_fn(function()
    api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  end, 2000) -- 2 seconds
end

---@param bufnr nil|integer
---@return nil|integer
M.buf_get_win = function(bufnr)
  for _, winnr in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(winnr) == bufnr then
      return winnr
    end
  end
end

---Source: https://github.com/stevearc/oil.nvim/blob/dd432e76d01eda08b8658415588d011009478469/lua/oil/layout.lua#L22C8-L22C8
---@return integer
M.get_editor_height = function()
  local editor_height = vim.o.lines - vim.o.cmdheight
  -- Subtract 1 if tabline is visible
  if vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #api.nvim_list_tabpages() > 1) then
    editor_height = editor_height - 1
  end
  -- Subtract 1 if statusline is visible
  if vim.o.laststatus >= 2 or (vim.o.laststatus == 1 and #api.nvim_tabpage_list_wins(0) > 1) then
    editor_height = editor_height - 1
  end
  return editor_height
end

---@param items table
---@param format function
---@return table
local function get_max_lengths(items, format)
  local max_lengths = {}
  for _, item in ipairs(items) do
    local formatted = format(item)
    for i, field in ipairs(formatted) do
      local field_length = string.len(field)
      max_lengths[i] = math.max(max_lengths[i] or 0, field_length)
    end
  end
  return max_lengths
end

---@param str string
---@param max_length number
---@param padding number|nil
---@return string
local function pad_string(str, max_length, padding)
  local padding_needed = max_length - string.len(str)

  if padding and padding_needed < padding then
    padding_needed = padding_needed + padding
  end

  if padding_needed > 0 then
    return str .. string.rep(" ", padding_needed)
  else
    return str
  end
end

---@param item table
---@param max_lengths table
---@return string
local function pad_item(item, max_lengths)
  local padded_item = {}
  for i, field in ipairs(item) do
    if max_lengths[i] then -- Skip padding if there's no max length for this field
      padded_item[i] = pad_string(field, max_lengths[i])
    else
      padded_item[i] = field
    end
  end
  return table.concat(padded_item, " │ ")
end

---@param items table
---@param opts table
---@return nil|table
function M.action_palette_selector(items, opts)
  log:trace("Opening selector")

  local max_lengths = get_max_lengths(items, opts.format)

  local select_opts = {
    prompt = opts.prompt,
    kind = "codecompanion.nvim",
    format_item = function(item)
      local formatted = opts.format(item)
      return pad_item(formatted, max_lengths)
    end,
  }

  -- Check if telescope exists and add telescope-specific options if available
  if pcall(require, "telescope.themes") then
    select_opts.telescope = require("telescope.themes").get_cursor({
      layout_config = {
        width = opts.width,
        height = opts.height,
      },
    })
  end

  vim.ui.select(items, select_opts, function(selected)
    if not selected then
      return
    end

    return opts.callback(selected)
  end)
end

---@param winnr number
---@param opts table
---@return table
function M.get_win_options(winnr, opts)
  local options = {}
  for k, _ in pairs(opts) do
    options[k] = api.nvim_get_option_value(k, { scope = "local", win = winnr })
  end

  return options
end

---@param winnr number
---@param opts table
---@return nil
function M.set_win_options(winnr, opts)
  for k, v in pairs(opts) do
    api.nvim_set_option_value(k, v, { scope = "local", win = winnr })
  end
end

--- Jump to an existing tab if the file is already opened.
--- Otherwise, open it in a new tab.
--- Returns the window ID after the jump.
---@param path string?
---@return integer
function M.tabnew_reuse(path)
  local uri
  if path then
    uri = vim.uri_from_fname(path)
  else
    uri = vim.uri_from_bufnr(0)
  end
  for _, tab in pairs(api.nvim_list_tabpages()) do
    for _, win in pairs(api.nvim_tabpage_list_wins(tab)) do
      local buf = api.nvim_win_get_buf(win)
      if vim.uri_from_bufnr(buf) == uri then
        api.nvim_set_current_win(win)
        return win
      end
    end
  end
  vim.cmd("tabnew " .. path)
  return api.nvim_get_current_win()
end

return M
