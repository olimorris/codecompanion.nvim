local log = require("codecompanion.utils.log")

local api = vim.api

local M = {}

---Open a floating window with the provided lines
---@param lines table
---@param opts table
---@return number,number The buffer and window numbers
M.create_float = function(lines, opts)
  local window = opts.window
  local width = window.width > 1 and window.width or opts.width or 85
  local height = window.height > 1 and window.height or opts.height or 17

  local bufnr = opts.bufnr or api.nvim_create_buf(false, true)

  require("codecompanion.utils").set_option(bufnr, "filetype", opts.filetype or "codecompanion")

  local winnr = api.nvim_open_win(bufnr, true, {
    relative = opts.relative or "cursor",
    border = "single",
    width = width,
    height = height,
    style = "minimal",
    row = 10,
    col = 0,
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

---@class ConfirmDialogOpts
---@field padding? number Content padding, default is 2
---@field max_width? number Maximum width of dialog, default is 70
---@field min_width? number Minimum width of dialog, default is 35
---@field title? string Dialog title, default is "Confirm"
---@field yes_icon? string YES button icon, default is " 󰄬 "
---@field no_icon? string NO button icon, default is " 󰅖 "
---@field yes_text? string YES button text, default is " 󰄬 YES"
---@field no_text? string NO button text, default is " 󰅖 NO"
---@field border? string|table Border style, default is "rounded"
---@field zindex? number Window z-index, default is 100
---@field relative? string Relative position, default is "editor"
---@field highlights? table<string, table> Custom highlight group configuration
---@field auto_close? boolean Whether to auto close when losing focus, default is true
---@field timeout? number Auto close delay timeout (milliseconds), default is 10

---Create a confirmation dialog floating window
---@param content string Content to display
---@param callback function Callback function that receives true/false/nil
---@param opts? ConfirmDialogOpts Optional configuration
---@return nil
function M.create_confirm_dialog(content, callback, opts)
  opts = opts or {}

  -- Define highlight group configuration
  local highlights = opts.highlights
    or {
      CodeCompanionConfirmYes = { fg = "#98c379", bg = "NONE", italic = false, bold = false },
      CodeCompanionConfirmNo = { fg = "#61afef", bg = "NONE", italic = false, bold = false },
      CodeCompanionConfirmSelected = { fg = "#e06c75", bg = "#3e4451", italic = false, bold = true },
    }

  -- Batch set highlight groups
  for name, hl in pairs(highlights) do
    vim.api.nvim_set_hl(0, name, hl)
  end

  -- Configuration parameters and theme
  local config = {
    padding = opts.padding or 2,
    max_width = opts.max_width or 70,
    min_width = opts.min_width or 35,
    yes_icon = opts.yes_icon or " 󰄬 ",
    no_icon = opts.no_icon or " 󰅖 ",
    yes_text = opts.yes_text or " 󰄬 YES",
    no_text = opts.no_text or " 󰅖 NO",
    border = opts.border or "rounded",
    zindex = opts.zindex or 100,
    relative = opts.relative or "editor",
    auto_close = opts.auto_close == nil and true or opts.auto_close,
    timeout = opts.timeout or 10,
  }

  -- Smart text wrapping function
  local function wrap_text(text, width)
    local lines, current_line = {}, ""
    for _, word in ipairs(vim.split(text, " ")) do
      local test_line = current_line == "" and word or (current_line .. " " .. word)
      if string.len(test_line) <= width then
        current_line = test_line
      else
        if current_line ~= "" then
          table.insert(lines, current_line)
        end
        current_line = word
      end
    end
    if current_line ~= "" then
      table.insert(lines, current_line)
    end
    return lines
  end

  -- Calculate dimensions
  local content_width = math.min(
    config.max_width - config.padding * 2,
    math.max(config.min_width - config.padding * 2, string.len(content))
  )
  local content_lines = wrap_text(content, content_width)
  local buttons_width = string.len(config.yes_text .. " " .. config.no_text) + 4
  local actual_width = math.max(
    math.max(unpack(vim.tbl_map(string.len, content_lines))) + config.padding * 2,
    config.min_width,
    buttons_width
  )
  local height = #content_lines + config.padding * 2

  -- Create display content
  local lines = {}
  -- Add top padding
  for i = 1, config.padding do
    table.insert(lines, "")
  end
  -- Add content (center aligned)
  for _, line in ipairs(content_lines) do
    local content_padding = math.floor((actual_width - string.len(line)) / 2)
    table.insert(lines, string.rep(" ", content_padding) .. line)
  end
  -- Add bottom padding
  for i = 1, config.padding do
    table.insert(lines, "")
  end

  -- Create buffer and window
  local bufnr = api.nvim_create_buf(false, true)
  local current_selection = 1

  -- Batch set buffer options
  local buffer_opts = {
    modifiable = false,
    bufhidden = "wipe",
    filetype = "codecompanion",
    buftype = "nofile",
  }
  for opt, value in pairs(buffer_opts) do
    vim.bo[bufnr][opt] = value
  end

  -- Create footer text function
  local function create_footer_text()
    local yes_hl = current_selection == 1 and "CodeCompanionConfirmSelected" or "CodeCompanionConfirmYes"
    local no_hl = current_selection == 2 and "CodeCompanionConfirmSelected" or "CodeCompanionConfirmNo"
    return {
      { config.yes_text, yes_hl },
      { " ", "Normal" },
      { config.no_text, no_hl },
    }
  end

  -- Create window
  local winnr = api.nvim_open_win(bufnr, true, {
    relative = config.relative,
    border = config.border,
    width = actual_width,
    height = height,
    style = "minimal",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - actual_width) / 2),
    title = opts.title or "Confirm",
    title_pos = "center",
    footer = create_footer_text(),
    footer_pos = "right",
    zindex = config.zindex,
  })

  -- Batch set window options
  local window_opts = {
    cursorline = false,
    wrap = false,
    spell = false,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
  }
  for opt, value in pairs(window_opts) do
    vim.wo[winnr][opt] = value
  end

  -- Set window highlight
  pcall(function()
    vim.wo[winnr].winhl = "Normal:Normal,FloatBorder:FloatBorder,FloatTitle:FloatTitle"
  end)

  -- Set content
  vim.bo[bufnr].modifiable = true
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  -- Update footer and close dialog functions
  local function update_footer()
    api.nvim_win_set_config(winnr, { footer = create_footer_text(), footer_pos = "right" })
  end

  local function close_dialog(result)
    if api.nvim_win_is_valid(winnr) then
      pcall(api.nvim_win_close, winnr, true)
    end
    if callback then
      callback(result)
    end
  end

  local function switch_selection(new_selection)
    if new_selection ~= current_selection then
      current_selection = new_selection
      update_footer()
    end
  end

  -- Keymap configuration
  local keymap_opts = { buffer = bufnr, silent = true, nowait = true }
  local keymaps = {
    -- Switch selection
    {
      { "<Tab>", "<S-Tab>" },
      function()
        switch_selection(current_selection == 1 and 2 or 1)
      end,
    },
    {
      { "<Left>", "h" },
      function()
        switch_selection(1)
      end,
    },
    {
      { "<Right>", "l" },
      function()
        switch_selection(2)
      end,
    },
    -- Confirm selection
    {
      "<CR>",
      function()
        close_dialog(current_selection == 1)
      end,
    },
    {
      "y",
      function()
        close_dialog(true)
      end,
    },
    {
      "n",
      function()
        close_dialog(false)
      end,
    },
    -- Cancel
    {
      { "<ESC>", "q" },
      function()
        close_dialog(nil)
      end,
    },
  }

  -- Batch set keymaps
  for _, keymap in ipairs(keymaps) do
    local keys, func = keymap[1], keymap[2]
    if type(keys) == "table" then
      for _, key in ipairs(keys) do
        vim.keymap.set("n", key, func, keymap_opts)
      end
    else
      vim.keymap.set("n", keys, func, keymap_opts)
    end
  end

  -- Set autocommands
  if config.auto_close then
    local augroup = api.nvim_create_augroup("ConfirmDialogFocus", { clear = true })
    api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
      group = augroup,
      buffer = bufnr,
      callback = function()
        vim.defer_fn(function()
          if api.nvim_win_is_valid(winnr) and api.nvim_get_current_win() ~= winnr then
            close_dialog(nil)
          end
        end, config.timeout)
      end,
    })

    api.nvim_create_autocmd("WinClosed", {
      group = augroup,
      pattern = tostring(winnr),
      callback = function()
        pcall(api.nvim_del_augroup_by_id, augroup)
      end,
    })
  end
end

return M
