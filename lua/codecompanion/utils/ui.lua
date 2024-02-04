local log = require("codecompanion.utils.log")

local api = vim.api

local M = {}

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

  for _, winid in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_is_valid(winid) and api.nvim_win_get_buf(winid) == bufnr then
      table.insert(wins, winid)
    end
  end

  return wins
end

---@param winid? number
M.scroll_to_end = function(winid)
  winid = winid or 0
  local bufnr = api.nvim_win_get_buf(winid)
  local lnum = api.nvim_buf_line_count(bufnr)
  local last_line = api.nvim_buf_get_lines(bufnr, -2, -1, true)[1]
  api.nvim_win_set_cursor(winid, { lnum, api.nvim_strwidth(last_line) })
end

---@param bufnr nil|integer
M.buf_scroll_to_end = function(bufnr)
  for _, winid in ipairs(M.buf_list_wins(bufnr or 0)) do
    M.scroll_to_end(winid)
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
function M.selector(items, opts)
  log:trace("Opening selector")

  local max_lengths = get_max_lengths(items, opts.format)

  vim.ui.select(items, {
    prompt = opts.prompt,
    kind = "codecompanion.nvim",
    telescope = require("telescope.themes").get_cursor({
      layout_config = {
        width = opts.width,
        height = opts.height,
      },
    }),
    format_item = function(item)
      local formatted = opts.format(item)
      return pad_item(formatted, max_lengths)
    end,
  }, function(selected)
    if not selected then
      return
    end

    return opts.callback(selected)
  end)
end

---@param opts table
---@param winid number
function M.set_options(opts, winid)
  for k, v in pairs(opts) do
    api.nvim_set_option_value(k, v, { scope = "local", win = winid })
  end
end

---@param bufnr number
---@param opts table
function M.open_float(bufnr, opts)
  local total_width = vim.o.columns
  local total_height = M.get_editor_height()
  local width = total_width - 2 * opts.display.padding
  if opts.display.border ~= "none" then
    width = width - 2 -- The border consumes 1 col on each side
  end
  if opts.display.max_width > 0 then
    width = math.min(width, opts.display.max_width)
  end

  local height = total_height - 2 * opts.display.padding
  if opts.display.max_height > 0 then
    height = math.min(height, opts.display.max_height)
  end

  local row = math.floor((total_height - height) / 2)
  local col = math.floor((total_width - width) / 2) - 1 -- adjust for border width

  local winid = api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = opts.display.border,
    zindex = 45,
    title = "Code Companion",
    title_pos = "center",
  })

  return winid
end

return M
