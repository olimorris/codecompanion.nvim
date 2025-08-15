local config = require("codecompanion.config")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")

local api = vim.api

local M = {}

---Check if a buffer is suitable for taking over
---@param buf_info table Buffer info from getbufinfo()
---@return boolean
local function is_suitable_buffer(buf_info)
  local buftype = vim.bo[buf_info.bufnr].buftype
  return buf_info.listed
    and buf_info.loaded
    and buftype ~= "terminal"
    and buftype ~= "help"
    and buftype ~= "quickfix"
    and buftype ~= "codecompanion"
end

---Check if a window is suitable (not floating)
---@param win_id number Window ID
---@return boolean
local function is_suitable_window(win_id)
  log:debug("[catalog::helpers::diff::create] Checking window %s", win_id)
  local cfg = api.nvim_win_get_config(win_id)
  -- Return false if it's floating (we want non-floating windows)
  return not ((cfg.relative ~= "" and cfg.relative ~= nil) or cfg.external == true)
end

---Find the best window for displaying a buffer
---@param target_bufnr number|nil The buffer we want to display (nil for file-only case)
---@return number|nil winnr The best window number, or nil if should use float
local function find_best_window_for_buffer(target_bufnr)
  -- 1. Check if buffer already visible (only if we have a buffer)
  if target_bufnr then
    local existing_win = ui.buf_get_win(target_bufnr)
    if existing_win then
      log:debug("[catalog::helpers::diff::create] Buffer %s already visible in window %s", target_bufnr, existing_win)
      return existing_win
    end
  end
  -- 2. Get all buffers sorted by most recently used
  local buffers = vim.fn.getbufinfo({ buflisted = 1 })
  table.sort(buffers, function(a, b)
    if a.lastused == b.lastused then
      return a.bufnr > b.bufnr -- fallback to buffer number for stable sort
    end
    return a.lastused > b.lastused -- most recent first
  end)
  -- 3. Find the most recently used buffer that's in a good window
  for _, buf_info in ipairs(buffers) do
    if is_suitable_buffer(buf_info) then
      for _, win_id in ipairs(buf_info.windows) do
        if is_suitable_window(win_id) then
          log:debug("[catalog::helpers::diff::create] Found suitable window %s for buffer %s", win_id, buf_info.bufnr)
          return win_id
        end
      end
    end
  end

  return nil -- fallback to float
end

---Open buffer or file in the specified window
---@param winnr number Window to use
---@param bufnr_or_filepath number|string Buffer number or file path
---@return number|nil bufnr The buffer number if successful
local function open_buffer_in_window(winnr, bufnr_or_filepath)
  local is_filepath = type(bufnr_or_filepath) == "string"
  if is_filepath then
    if not vim.fn.filereadable(bufnr_or_filepath) then
      log:warn("[catalog::helpers::diff::create] File not readable: %s", bufnr_or_filepath)
      return nil
    end
    local ok = pcall(api.nvim_win_call, winnr, function()
      vim.cmd.edit(vim.fn.fnameescape(bufnr_or_filepath))
    end)
    if not ok then
      log:warn("[catalog::helpers::diff::create] Failed to open file: %s", bufnr_or_filepath)
      return nil
    end
    return api.nvim_win_get_buf(winnr)
  else
    local bufnr = bufnr_or_filepath --[[@as number|nil]]
    local ok = pcall(api.nvim_win_set_buf, winnr, bufnr)
    if not ok then
      log:warn("[catalog::helpers::diff::create] Failed to set buffer in window")
      return nil
    end
    return bufnr
  end
end

---Create a diff for a buffer or file and set up keymaps
---@param bufnr_or_filepath number|string The buffer number or file path to create diff for
---@param diff_id number|string Unique identifier for this diff
---@param opts? table Optional configuration
---@original_content: string[] The original buffer content before changes (optional)
---@return table|nil diff The diff object, or nil if no diff was created
function M.create(bufnr_or_filepath, diff_id, opts)
  opts = opts or {}

  local is_filepath = type(bufnr_or_filepath) == "string"
  local existing_bufnr
  if is_filepath then
    local bufnr = vim.fn.bufnr(bufnr_or_filepath)
    existing_bufnr = (bufnr ~= -1) and bufnr or nil
  else
    existing_bufnr = bufnr_or_filepath --[[@as number|nil]]
  end
  log:debug("[catalog::helpers::diff::create] Called - diff_id=%s", tostring(diff_id))

  if vim.g.codecompanion_auto_tool_mode or not config.display.diff.enabled then
    log:debug(
      "[catalog::helpers::diff::create] Skipping diff - auto_mode=%s, enabled=%s",
      tostring(vim.g.codecompanion_auto_tool_mode),
      tostring(config.display.diff.enabled)
    )
    return nil
  end
  -- Check if existing buffer is terminal (skip terminal buffers)
  if existing_bufnr and type(existing_bufnr) == "number" and existing_bufnr > 0 then
    local ok, buftype = pcall(function()
      return vim.bo[existing_bufnr].buftype
    end)
    if ok and buftype == "terminal" then
      log:debug("[catalog::helpers::diff::create] Skipping diff - terminal buffer")
      return nil
    elseif not ok then
      log:debug("[catalog::helpers::diff::create] Could not check buftype for buffer %s", existing_bufnr)
    end
  end

  local provider = config.display.diff.provider
  local ok, diff_module = pcall(require, "codecompanion.providers.diff." .. provider)
  if not ok then
    log:error("[catalog::helpers::diff::create] Failed to load provider '%s'", provider)
    return nil
  end

  -- Find the best window for displaying the buffer/file
  local winnr = find_best_window_for_buffer(existing_bufnr)
  local bufnr
  if winnr then
    log:debug("[catalog::helpers::diff::create] Using window %s for diff", winnr)
    bufnr = open_buffer_in_window(winnr, existing_bufnr or bufnr_or_filepath)
    if not bufnr then
      log:warn("[catalog::helpers::diff::create] Failed to open buffer/file in window %s", winnr)
      return nil
    end
    pcall(api.nvim_set_current_win, winnr)
  else
    vim.cmd("topleft vnew")
    winnr = api.nvim_get_current_win()
    bufnr = open_buffer_in_window(winnr, bufnr_or_filepath)
    if not bufnr then
      pcall(vim.cmd, "close")
      log:warn("[catalog::helpers::diff::create] Failed to open buffer/file in new window")
      return nil
    end
  end

  -- Use provided content or fallback to current buffer content
  local original_content = opts.original_content or api.nvim_buf_get_lines(bufnr, 0, -1, true)

  local diff_args = {
    bufnr = bufnr,
    contents = original_content,
    filetype = api.nvim_get_option_value("filetype", { buf = bufnr }),
    id = diff_id,
    winnr = winnr,
  }

  local diff = diff_module.new(diff_args)

  if diff then
    M.setup_keymaps(diff, opts)
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

  -- Store existing keymaps that might conflict
  local existing_maps = {}
  for _, keymap_config in pairs(inline_config.keymaps) do
    for mode, lhs in pairs(keymap_config.modes) do
      -- Check if a buffer-local mapping exists for this buffer
      local existing = vim.fn.maparg(lhs, mode, false, true)
      if existing and existing ~= {} then
        local is_buffer_local = existing.buffer and (existing.buffer == 1 or existing.buffer == diff.bufnr)
        if is_buffer_local then
          local key = mode .. ":" .. lhs
          existing_maps[key] = existing
          pcall(vim.keymap.del, mode, lhs, { buffer = diff.bufnr })
        end
      end
    end
  end
  diff._original_keymaps = existing_maps
  if vim.tbl_count(existing_maps) > 0 then
    log:debug(
      "[catalog::helpers::diff::setup_keymaps] Stored %d original keymaps for restoration",
      vim.tbl_count(existing_maps)
    )
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
