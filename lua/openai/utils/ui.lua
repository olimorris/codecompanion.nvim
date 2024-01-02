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

---@param strategies table
---@param items table
local function picker(strategies, items)
  if not items then
    items = config.static_commands
  end

  local name_pad = get_max_length(items, "name")
  local strat_pad = get_max_length(items, "strategy")

  vim.ui.select(items, {
    prompt = "OpenAI.nvim",
    kind = "openai.nvim",
    format_item = function(item)
      return pad_string(item.name, name_pad)
        .. " │ "
        .. pad_string(item.strategy, strat_pad)
        .. " │ "
        .. item.description
    end,
  }, function(selected)
    if not selected then
      return
    end

    return strategies[selected.strategy](selected.opts, selected.prompts)
  end)
end

---@param strategies table
---@param items table
function M.select(strategies, items)
  log:trace("Opening picker")

  --TODO: Put user Autocmd here
  picker(strategies, items)
end

---@param code string
local function split(code)
  if not code or code == "" then
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(code, "\n"))
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  local height = math.floor(vim.o.lines * 0.4)
  local current_win = vim.api.nvim_get_current_win()

  vim.cmd(height .. "new")
  local split_win = vim.api.nvim_get_current_win()

  vim.api.nvim_win_set_buf(split_win, buf)
  vim.api.nvim_win_set_option(split_win, "wrap", true)

  -- Set up a keymap for 'q' to close the window
  vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
    noremap = true,
    silent = true,
    callback = function()
      vim.api.nvim_win_close(split_win, true)
      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  })

  -- Return to the original window
  vim.api.nvim_set_current_win(current_win)
end

---@param opts table
---@param code string
local function popup(opts, code)
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
  local win_width = math.floor(vim.o.columns * (opts.width or 0.8))
  local win_height = math.floor(vim.o.lines * (opts.height or 0.8))
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

---@param opts table
---@param code string
function M.display(opts, code)
  if opts.type == "split" then
    split(code)
  elseif opts.type == "popup" then
    popup(opts, code)
  end
end

return M
