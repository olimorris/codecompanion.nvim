local config = require("openai.config")
local log = require("openai.utils.log")

local M = {}

---@param tbl table
---@param field string
local function get_max_length(tbl, field)
  local max_length = 0
  for _, str in ipairs(tbl) do
    local len = string.len(str[field])
    if len > max_length then
      max_length = len
    end
  end

  return max_length
end

---@param str string
---@param max_length number
local function pad_string(str, max_length)
  local padding_needed = max_length - string.len(str)
  if padding_needed > 0 then
    -- Append the necessary padding
    return str .. string.rep(" ", padding_needed)
  else
    return str
  end
end

---@param context table
---@param items table
local function picker(context, items)
  if not items then
    items = config.static_commands
  end

  local name_pad = get_max_length(items, "name")
  local mode_pad = get_max_length(items, "mode")

  vim.ui.select(items, {
    prompt = "OpenAI.nvim",
    kind = "openai.nvim",
    format_item = function(item)
      return pad_string(item.name, name_pad)
        .. " │ "
        .. pad_string(item.mode, mode_pad)
        .. " │ "
        .. item.description
    end,
  }, function(selected)
    if not selected then
      return
    end

    return selected.action(context)
  end)
end

---@param context table
---@param items table
function M.select(context, items)
  log:trace("Opening picker")
  log:trace("Context: %s", context)

  --TODO: Put user Autocmd here
  picker(context, items)
end

function M.split(code)
  -- Create a new buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(code, "\n"))
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  -- Calculate height for the split
  local height = math.floor(vim.o.lines * 0.4)

  -- Save the current window id to come back to it later
  local current_win = vim.api.nvim_get_current_win()

  -- Create the bottom split and set its buffer to the new one
  vim.cmd(height .. "new")
  local split_win = vim.api.nvim_get_current_win()

  -- Set the newly created buffer to the split window
  vim.api.nvim_win_set_buf(split_win, buf)

  -- Enable text wrapping in the split window
  vim.api.nvim_win_set_option(split_win, "wrap", true)

  -- Set up a keymap for 'q' to close the window
  vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
    noremap = true,
    silent = true,
    callback = function()
      vim.api.nvim_win_close(split_win, true)
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end,
  })

  -- Return to the original window
  vim.api.nvim_set_current_win(current_win)
end

function M.popup(code)
  -- Create a new buffer
  local buf = vim.api.nvim_create_buf(false, true)

  -- Set the buffer's filetype to markdown
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")

  -- Add the generated code to the buffer
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(code, "\n"))

  -- Prevent modifications to the buffer
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")

  -- Define the floating window size and position
  local win_width = math.floor(vim.o.columns * 0.8)
  local win_height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - win_height) / 2)
  local col = math.floor((vim.o.columns - win_width) / 2)

  -- Open a new floating window
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

  vim.api.nvim_win_set_option(win, "wrap", true)

  vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
    noremap = true,
    silent = true,
    callback = function()
      vim.api.nvim_win_close(win, true)
    end,
  })
end

return M
