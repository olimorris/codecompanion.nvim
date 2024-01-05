local log = require("codecompanion.utils.log")

local M = {}

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

---@param win number
---@param bufnr number|nil
local function close(win, bufnr)
  vim.api.nvim_win_close(win, true)
  if bufnr then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

local function set_keymaps(win, bufnr, client, conversation)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "q", "", {
    noremap = true,
    silent = true,
    callback = function()
      close(win)
    end,
  })

  vim.api.nvim_buf_set_keymap(bufnr, "n", "c", "", {
    noremap = true,
    silent = true,
    callback = function()
      close(win)
      return require("codecompanion.strategy.chat").new({
        client = client,
        messages = conversation,
        show_buffer = true,
      })
    end,
  })
end

---@param response string
---@param conversation table
---@param client CodeCompanion.Client
local function split(response, conversation, client)
  if not response or response == "" then
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(response, "\n"))
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  local height = math.floor(vim.o.lines * 0.4)
  local current_win = vim.api.nvim_get_current_win()

  vim.cmd(height .. "new")
  local win = vim.api.nvim_get_current_win()

  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_option(win, "wrap", true)
  set_keymaps(win, buf, client, conversation)

  vim.api.nvim_set_current_win(current_win)
end

---@param opts table
---@param response string
---@param conversation table
---@param client CodeCompanion.Client
local function popup(opts, response, conversation, client)
  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(response, "\n"))
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")

  local win_width = math.floor(vim.o.columns * (opts.width or 0.8))
  local win_height = math.floor(vim.o.lines * (opts.height or 0.8))
  local row = math.floor((vim.o.lines - win_height) / 2)
  local col = math.floor((vim.o.columns - win_width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = win_width,
    height = win_height,
    row = row,
    col = col,
    border = "single",
    style = "minimal",
    noautocmd = true,
  })

  set_keymaps(win, buf, client, conversation)
  vim.api.nvim_win_set_option(win, "wrap", true)
end

---@param opts table
---@param response string
---@param client CodeCompanion.Client
function M.display(opts, response, conversation, client)
  if opts.type == "split" then
    split(response, conversation, client)
  elseif opts.type == "popup" then
    popup(opts, response, conversation, client)
  end
end

return M
