local config = require("codecompanion.config")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")
local api = vim.api

local M = {}

---Create a diff for a buffer and set up keymaps
---@param bufnr number The buffer to create diff for
---@param diff_id number|string Unique identifier for this diff
---@param opts? table Optional configuration
---@original_content: string[] The original buffer content before changes (optional)
---@return table|nil diff The diff object, or nil if no diff was created
function M.create(bufnr, diff_id, opts)
  opts = opts or {}

  log:debug("[Diff] create() called - bufnr=%d, diff_id=%s", bufnr, tostring(diff_id))

  -- Skip if in auto mode or diff disabled
  if vim.g.codecompanion_auto_tool_mode or not config.display.diff.enabled then
    log:debug(
      "[Diff] Skipping diff - auto_mode=%s, enabled=%s",
      tostring(vim.g.codecompanion_auto_tool_mode),
      tostring(config.display.diff.enabled)
    )
    return nil
  end

  -- Skip for terminal buffers
  if vim.bo[bufnr].buftype == "terminal" then
    log:debug("[Diff] Skipping diff - terminal buffer")
    return nil
  end

  local provider = config.display.diff.provider
  log:debug("[Diff] Using provider: %s", provider)

  local ok, diff_module = pcall(require, "codecompanion.providers.diff." .. provider)
  if not ok then
    log:error("[Diff] Failed to load provider '%s': %s", provider, diff_module)
    return nil
  end
  log:debug("[Diff] Successfully loaded provider module")

  local winnr = ui.buf_get_win(bufnr)
  if not winnr then
    log:debug("[Diff] No window found for buffer %d", bufnr)
    return nil
  end

  -- Use provided original content or fallback to current buffer content
  local original_content = opts.original_content or api.nvim_buf_get_lines(bufnr, 0, -1, true)
  local current_content = api.nvim_buf_get_lines(bufnr, 0, -1, true)

  log:debug("[Diff] Original content lines: %d", #original_content)
  log:debug("[Diff] Current content lines: %d", #current_content)
  log:debug("[Diff] Using provided original_content: %s", opts.original_content and "YES" or "NO")

  if #original_content > 0 then
    log:debug("[Diff] Original first line: %s", original_content[1])
  end
  if #current_content > 0 then
    log:debug("[Diff] Current first line: %s", current_content[1])
  end

  local diff_args = {
    bufnr = bufnr,
    contents = original_content,
    filetype = api.nvim_get_option_value("filetype", { buf = bufnr }),
    id = diff_id,
    winnr = winnr,
  }

  log:debug(
    "[Diff] Creating diff with args: bufnr=%d, contents_lines=%d, filetype=%s",
    diff_args.bufnr,
    #diff_args.contents,
    diff_args.filetype
  )

  local diff = diff_module.new(diff_args)

  if diff then
    log:debug("[Diff] Successfully created diff object")
    M.setup_keymaps(diff, opts)
    log:debug("[Diff] Keymaps setup complete")
  else
    log:error("[Diff] Failed to create diff object")
  end

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
