local async = require("plenary.async")
local log = require("codecompanion.utils.log")

local api = vim.api

local M = {}

---@class CodeCompanion.WindowOpts
---@field bufnr? number Buffer number to use
---@field row? number Row position of the floating window
---@field col? number Column position of the floating window
---@field ft? string Filetype to set for the buffer
---@field ignore_keymaps? boolean Whether to ignore default keymaps
---@field lock? boolean Whether to lock the buffer (non-modifiable)
---@field opts? table Window options to set
---@field overwrite_buffer? boolean Whether to overwrite the buffer content
---@field relative? string Relative position of the floating window
---@field style? string Style of the floating window
---@field title? string Title of the floating window
---@field width? number Default width if not specified in window
---@field height? number Default height if not specified in window

---Open a floating window with the provided lines
---@param lines table
---@param opts CodeCompanion.WindowOpts
---@return number,number The buffer and window numbers
M.create_float = function(lines, opts)
  local cols = function()
    return vim.o.columns
  end
  local rows = function()
    return vim.o.lines
  end

  if type(opts.height) == "function" then
    opts.height = opts.height()
  end
  if type(opts.width) == "function" then
    opts.width = opts.width()
  end
  if type(opts.height) == "string" then
    opts.height = rows()
  end
  if type(opts.width) == "string" then
    opts.width = cols()
  end

  local width = opts.width
  if width and width > 0 and width < 1 then
    width = math.floor(cols() * width)
  end
  width = (width and width >= 1 and width or opts.width or 85) ---@cast width number

  local height = opts.height
  if height and height > 0 and height < 1 then
    height = math.floor(rows() * height)
  end
  height = (height and height >= 1 and height or opts.height or 17) ---@cast height number

  local bufnr = opts.bufnr or api.nvim_create_buf(false, true)
  api.nvim_set_option_value("filetype", opts.ft or "codecompanion", { buf = bufnr })

  -- Calculate center position if not specified
  local row = opts.row or opts.row ---@cast row number
  local col = opts.col or opts.col ---@cast col number
  if not row or not col then
    row = math.floor((rows() - height) / 2 - 1) -- Account for status line for better UX
    col = math.floor((cols() - width) / 2)
  end

  local winnr = api.nvim_open_win(bufnr, true, {
    relative = opts.relative or "editor",
    -- thanks to @mini.nvim for this, it's for >= 0.11, to respect users winborder style
    border = (vim.fn.exists("+winborder") == 0 or vim.o.winborder == "") and "single" or nil,
    width = width,
    height = height,
    style = opts.style,
    row = row,
    col = col,
    title = opts.title and (" " .. opts.title .. " ") or " Options ",
    title_pos = "center",
  })

  if not opts.bufnr or opts.overwrite_buffer ~= false then
    api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end

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

  -- Set some sensible keymaps for closing the window

  local function close()
    pcall(function()
      api.nvim_win_close(winnr, true)
      api.nvim_buf_delete(bufnr, { force = true })
    end)
  end

  vim.keymap.set("n", "q", close, { buffer = bufnr })

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

---@param bufnr nil|number
---@return number[]
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

---@param bufnr nil|number
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

---@param bufnr nil|number
---@return nil|number
M.buf_get_win = function(bufnr)
  for _, winnr in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(winnr) == bufnr then
      return winnr
    end
  end
end

---Source: https://github.com/stevearc/oil.nvim/blob/dd432e76d01eda08b8658415588d011009478469/lua/oil/layout.lua#L22C8-L22C8
---@return number
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
---@return number
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

---Set a winbar for a specific window
---@param winnr number
---@param text string Text to set in the winbar
---@param hl string Highlight group to use for the winbar
---@return nil
function M.set_winbar(winnr, text, hl)
  if not vim.api.nvim_win_is_valid(winnr) then
    return
  end

  local centered = "%=" .. (text or ""):gsub("%%", "%%%%") .. "%="
  local existing_hl = vim.wo[winnr].winhighlight or ""
  existing_hl = #existing_hl > 0 and existing_hl .. "," or existing_hl
  vim.wo[winnr].winhighlight = existing_hl .. "WinBar:" .. hl .. ",WinBarNC:" .. hl
  vim.wo[winnr].winbar = centered
end

---@type table<any, table<number, { cancel?: fun(), winnr?: number, ts: number, prompt?: string, choices?: table, callback?: fun(value: any|nil), opts?: table }>>
---Registry of confirm dialogs: key -> { [id] = entry }
---Entries with `winnr` are currently shown; entries without are queued.
local pending_confirms = {}

---Cancel all open confirm dialogs for a given key
---@param key any The key used when creating the confirm dialogs
function M.cancel_confirm(key)
  local group = pending_confirms[key]
  if not group then
    return
  end
  pending_confirms[key] = nil
  for _, entry in pairs(group) do
    if entry.cancel then
      entry.cancel()
    end
  end
end

---Focus the currently visible confirm dialog window.
---@return boolean focused Whether a window was focused
function M.focus_confirm()
  for _, group in pairs(pending_confirms) do
    for _, entry in pairs(group) do
      if entry.winnr and api.nvim_win_is_valid(entry.winnr) then
        api.nvim_set_current_win(entry.winnr)
        return true
      end
    end
  end
  return false
end

---Show the next queued confirm dialog (oldest first).
---Called automatically after a dialog is resolved.
---@return boolean shown Whether a queued dialog was shown
function M.show_next_queued()
  local oldest_entry, oldest_key, oldest_id
  for k, group in pairs(pending_confirms) do
    for id, entry in pairs(group) do
      if not entry.winnr then
        if not oldest_entry or entry.ts < oldest_entry.ts then
          oldest_entry = entry
          oldest_key = k
          oldest_id = id
        end
      end
    end
  end

  if not oldest_entry then
    return false
  end

  -- Remove the queued entry before re-calling confirm
  if pending_confirms[oldest_key] then
    pending_confirms[oldest_key][oldest_id] = nil
    if next(pending_confirms[oldest_key]) == nil then
      pending_confirms[oldest_key] = nil
    end
  end

  M.confirm(oldest_entry.prompt, oldest_entry.choices, oldest_entry.callback, oldest_entry.opts)
  return true
end

---Normalize a choice entry into { label: string, value: any }
---Accepts either a plain string or a table with label/value/default fields.
---@param choice string|{ label: string, value?: any, default?: boolean }
---@return { label: string, value: any, default?: boolean }
local function normalize_choice(choice)
  if type(choice) == "string" then
    return { label = choice, value = choice }
  end
  return { label = choice.label, value = choice.value or choice.label, default = choice.default }
end

---Create the footer with button highlights for the confirm dialog
---@param choices table The list of normalized choice objects
---@param active_idx number The 1-based index of the currently active choice
---@param focus_hint? string Optional focus keymap hint to show at the right
---@return table footer The footer spec for nvim_open_win / nvim_win_set_config
local function create_confirm_footer(choices, active_idx, focus_hint)
  local footer = { { " ", "FloatBorder" } }
  for i, choice in ipairs(choices) do
    if i > 1 then
      table.insert(footer, { " ", "FloatBorder" })
    end
    local hl = (i == active_idx) and "CodeCompanionButtonActive" or "CodeCompanionButtonInactive"
    table.insert(footer, { " " .. choice.label .. " ", hl })
  end
  if focus_hint then
    table.insert(footer, { "  " .. focus_hint .. " to focus ", "Comment" })
  end
  table.insert(footer, { " ", "FloatBorder" })

  return footer
end

---Confirmation dialog that is rendered as a floating window.
---Navigate with Tab/S-Tab, confirm with Enter, dismiss with Esc/q, or press 1-9 for direct selection.
---@param prompt string The prompt message (supports markdown syntax highlighting)
---@param choices table List of choices — each can be a string or { label: string, value?: any, default?: boolean }
---@param callback fun(value: any|nil) Called with the value of the selected choice, or nil if cancelled
---@param opts? { key: any, title: string } Options. `key` tracks the dialog for `cancel_confirm`. `title` sets the window title.
---@return fun() cancel A function that closes the dialog (calling callback with nil)
function M.confirm(prompt, choices, callback, opts)
  opts = opts or {}
  local key = opts.key

  local id = math.random(1000000)

  -- Check if there is already a visible dialog — if so, queue this one
  local has_visible = false
  for _, group in pairs(pending_confirms) do
    for _, entry in pairs(group) do
      if entry.winnr and api.nvim_win_is_valid(entry.winnr) then
        has_visible = true
        break
      end
    end
    if has_visible then
      break
    end
  end

  if has_visible and key then
    if not pending_confirms[key] then
      pending_confirms[key] = {}
    end
    pending_confirms[key][id] = {
      ts = vim.uv.hrtime(),
      prompt = prompt,
      choices = choices,
      callback = callback,
      opts = opts,
    }
    return function()
      if pending_confirms[key] then
        pending_confirms[key][id] = nil
        if next(pending_confirms[key]) == nil then
          pending_confirms[key] = nil
        end
      end
    end
  end

  -- Normalize choices into { label, value, default } objects
  local normalized = {}
  local active = 1
  for i, choice in ipairs(choices) do
    normalized[i] = normalize_choice(choice)
    if normalized[i].default then
      active = i
    end
  end
  choices = normalized

  local lines = {}
  for _, line in ipairs(vim.split(prompt, "\n")) do
    table.insert(lines, line)
  end

  -- Calculate window dimensions
  local max_line_width = 0
  for _, line in ipairs(lines) do
    max_line_width = math.max(max_line_width, api.nvim_strwidth(line))
  end
  local footer_width = 0
  for _, choice in ipairs(choices) do
    footer_width = footer_width + api.nvim_strwidth(choice.label) + 3
  end
  footer_width = footer_width + 1

  local window_config = require("codecompanion.config").display.chat.tool_approval_window

  -- Determine anchor: "window" positions over the chat window, "editor" centers on the full editor
  local anchor_winnr
  if window_config.relative == "window" and type(key) == "number" then
    local win_id = vim.fn.bufwinid(key)
    if win_id > 0 and api.nvim_win_is_valid(win_id) then
      anchor_winnr = win_id
    end
  end

  local ref_width, ref_height
  if anchor_winnr then
    ref_width = api.nvim_win_get_width(anchor_winnr)
    ref_height = api.nvim_win_get_height(anchor_winnr)
  else
    ref_width = vim.o.columns
    ref_height = vim.o.lines
  end

  local cfg_width = window_config.width
  local cfg_height = window_config.height
  if type(cfg_width) == "function" then
    cfg_width = cfg_width()
  end
  if type(cfg_height) == "function" then
    cfg_height = cfg_height()
  end

  local max_width = math.min(math.floor(ref_width * cfg_width), ref_width - 2)
  local max_height = math.min(math.floor(ref_height * cfg_height), ref_height - 4)

  local width = math.min(math.max(max_line_width + 4, footer_width), max_width)
  local height = math.min(math.max(#lines, 1), max_height)

  -- Create buffer with markdown filetype for syntax highlighting
  local bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].bufhidden = "wipe"

  -- Open floating window without focus, positioned over the chat window when possible
  local win_opts = {
    width = width,
    height = height,
    style = window_config.style,
    border = window_config.border,
    footer = create_confirm_footer(choices, active),
    footer_pos = "center",
  }
  local title_left = " " .. (opts.title or "Confirm") .. " "
  if window_config.focus_keymap then
    local hint = " " .. window_config.focus_keymap .. " to focus "
    local pad_len = math.max(0, width - api.nvim_strwidth(title_left) - api.nvim_strwidth(hint))
    win_opts.title = { { title_left, "FloatTitle" }, { string.rep(" ", pad_len), "FloatBorder" }, { hint, "Comment" } }
  else
    win_opts.title = { { title_left, "FloatTitle" } }
  end
  win_opts.title_pos = "left"
  if anchor_winnr then
    win_opts.relative = "win"
    win_opts.win = anchor_winnr
    win_opts.row = math.floor((ref_height - height) / 2)
    win_opts.col = math.floor((ref_width - width) / 2)
  else
    win_opts.relative = "editor"
    win_opts.row = math.floor((vim.o.lines - height) / 2) - 1
    win_opts.col = math.floor((vim.o.columns - width) / 2)
  end

  -- Auto-focus if the user is already in the chat window
  local auto_focus = anchor_winnr and api.nvim_get_current_win() == anchor_winnr
  local winnr = api.nvim_open_win(bufnr, auto_focus or false, win_opts)
  M.set_win_options(winnr, window_config.opts)

  local function update_footer()
    if api.nvim_win_is_valid(winnr) then
      api.nvim_win_set_config(winnr, {
        footer = create_confirm_footer(choices, active),
      })
    end
  end

  local closed = false
  local function close(value, skip_callback)
    if closed then
      return
    end
    closed = true
    if key and pending_confirms[key] then
      pending_confirms[key][id] = nil
      if next(pending_confirms[key]) == nil then
        pending_confirms[key] = nil
      end
    end
    pcall(api.nvim_win_close, winnr, true)
    if not skip_callback then
      vim.schedule(function()
        callback(value)
        M.show_next_queued()
      end)
    end
  end

  -- Navigation and selection keymaps
  local map_opts = { buffer = bufnr, nowait = true, silent = true }

  vim.keymap.set("n", "<Tab>", function()
    active = (active % #choices) + 1
    update_footer()
  end, map_opts)
  vim.keymap.set("n", "<S-Tab>", function()
    active = ((active - 2) % #choices) + 1
    update_footer()
  end, map_opts)
  vim.keymap.set("n", "<CR>", function()
    close(choices[active].value)
  end, map_opts)
  vim.keymap.set("n", "<Esc>", function()
    close(nil)
  end, map_opts)
  vim.keymap.set("n", "q", function()
    close(nil)
  end, map_opts)

  for i = 1, math.min(#choices, 9) do
    vim.keymap.set("n", tostring(i), function()
      close(choices[i].value)
    end, map_opts)
  end

  -- Handle window being closed externally
  api.nvim_create_autocmd("WinClosed", {
    buffer = bufnr,
    once = true,
    callback = function()
      close(nil)
    end,
  })

  local cancel = function()
    close(nil, true)
  end

  if key then
    if not pending_confirms[key] then
      pending_confirms[key] = {}
    end
    pending_confirms[key][id] = { cancel = cancel, winnr = winnr, ts = vim.uv.hrtime() }
  end

  return cancel
end

---Wait for user input via vim.ui.input, wrapped in plenary.async
---@param opts table Options for vim.ui.input
---@param callback fun(input: string|nil)
---@return nil
M.input = async.wrap(function(opts, callback)
  --Ref: https://github.com/CopilotC-Nvim/CopilotChat.nvim/blob/7a8e238e36ea9e1df9d6309434a37bcdc15a9fae/lua/CopilotChat/utils.lua#L148
  local fn = function()
    vim.ui.input(opts, function(input)
      if input == nil or input == "" then
        callback(nil)
        return
      end
      callback(input)
    end)
  end

  if vim.in_fast_event() then
    vim.schedule(fn)
  else
    fn()
  end
end, 2)

return M
