local config = require("codecompanion.config")
local keymaps = require("codecompanion.utils.keymaps")
local ui = require("codecompanion.utils.ui")
local api = vim.api

local M = {}

---Create a diff for a buffer and set up keymaps
---@param bufnr number The buffer to create diff for
---@param diff_id number|string Unique identifier for this diff
---@param opts? table Optional configuration
---@return table|nil diff The diff object, or nil if no diff was created
function M.create(bufnr, diff_id, opts)
  opts = opts or {}

  -- Skip if in auto mode or diff disabled
  if vim.g.codecompanion_auto_tool_mode or not config.display.diff.enabled then
    return nil
  end

  -- Skip for terminal buffers
  if vim.bo[bufnr].buftype == "terminal" then
    return nil
  end

  local provider = config.display.diff.provider
  local ok, diff_module = pcall(require, "codecompanion.providers.diff." .. provider)
  if not ok then
    return nil
  end

  local winnr = ui.buf_get_win(bufnr)
  if not winnr then
    return nil
  end

  local diff_args = {
    bufnr = bufnr,
    contents = api.nvim_buf_get_lines(bufnr, 0, -1, true),
    filetype = api.nvim_buf_get_option(bufnr, "filetype"),
    id = diff_id,
    winnr = winnr,
  }

  local diff = diff_module.new(diff_args)

  M.setup_keymaps(diff, opts)

  return diff
end

---Set up keymaps for the diff
---@param diff table The diff object
---@param opts? table Optional configuration
function M.setup_keymaps(diff, opts)
  opts = opts or {}

  local inline_config = config.strategies.inline
  if not inline_config or not inline_config.keymaps then
    return
  end

  keymaps
    .new({
      bufnr = diff.bufnr,
      callbacks = require("codecompanion.strategies.inline.keymaps"),
      data = { diff = diff },
      keymaps = inline_config.keymaps,
    })
    :set()
end

---Check if a diff should be created for this context
---@param bufnr number
---@return boolean should_create
---@return string|nil reason Why diff creation was skipped
function M.should_create(bufnr)
  if vim.g.codecompanion_auto_tool_mode then
    return false, "auto_tool_mode"
  end

  if not config.display.diff.enabled then
    return false, "diff_disabled"
  end

  if vim.bo[bufnr].buftype == "terminal" then
    return false, "terminal_buffer"
  end

  return true, nil
end

return M
