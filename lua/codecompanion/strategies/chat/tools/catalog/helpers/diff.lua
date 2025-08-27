local config = require("codecompanion.config")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")

local api = vim.api

local M = {}

---Check if a buffer is suitable for taking over
---@param buf_info table Buffer info from getbufinfo()
---@return boolean
local function is_correct_buftype(buf_info)
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

---Check if buffer exists for a file path
---@param filepath string
---@return number|nil bufnr Buffer number if exists, nil otherwise
local function get_existing_buffer(filepath)
  local bufnr = vim.fn.bufnr(filepath)
  return bufnr ~= -1 and bufnr or nil
end

---Find a suitable window for displaying content
---@return number|nil winnr Window number if found
local function find_suitable_window()
  local buffers = vim.fn.getbufinfo({ buflisted = 1 })
  table.sort(buffers, function(a, b)
    if a.lastused == b.lastused then
      return a.bufnr > b.bufnr
    end
    return a.lastused > b.lastused
  end)

  for _, buf_info in ipairs(buffers) do
    if is_correct_buftype(buf_info) then
      for _, win_id in ipairs(buf_info.windows) do
        if is_suitable_window(win_id) then
          return win_id
        end
      end
    end
  end

  return nil
end

---Open buffer in existing window
---@param bufnr number
---@param winnr number
---@return number bufnr
local function use_buffer_in_window(bufnr, winnr)
  log:debug("[catalog::helpers::diff::create] Using buffer %d in window %d", bufnr, winnr)
  pcall(api.nvim_set_current_win, winnr)

  return bufnr
end

---Set existing buffer in a window
---@param bufnr number
---@param winnr number
---@return number|nil bufnr
local function set_buffer_in_window(bufnr, winnr)
  log:debug("[catalog::helpers::diff::create] Setting buffer %d in window %d", bufnr, winnr)

  local ok = pcall(api.nvim_win_set_buf, winnr, bufnr)
  if ok then
    pcall(api.nvim_set_current_win, winnr)
    return bufnr
  end

  log:debug("[catalog::helpers::diff::create] Failed to set buffer %d in window %d", bufnr, winnr)
  return nil
end

---Create new buffer from file in window
---@param filepath string
---@param winnr number
---@return number|nil bufnr
local function create_buffer_in_window(filepath, winnr)
  if not vim.fn.filereadable(filepath) then
    log:debug("[catalog::helpers::diff::create] File not readable: %s", filepath)
    return nil
  end

  log:debug("[catalog::helpers::diff::create] Creating buffer for file: %s in window %d", filepath, winnr)
  local ok = pcall(api.nvim_win_call, winnr, function()
    vim.cmd.edit(vim.fn.fnameescape(filepath))
    vim.schedule(function()
      pcall(api.nvim_set_current_win, winnr)
    end)
  end)

  if ok then
    return api.nvim_win_get_buf(winnr)
  end

  log:warn("[catalog::helpers::diff::create] Failed to create buffer for: %s", filepath)
  return nil
end

---Create new split window with buffer
---@param bufnr_or_filepath number|string
---@return number|nil bufnr
local function create_split_window(bufnr_or_filepath)
  vim.cmd("topleft vnew")
  local winnr = api.nvim_get_current_win()

  if type(bufnr_or_filepath) == "string" then
    local bufnr = create_buffer_in_window(bufnr_or_filepath, winnr)
    if not bufnr then
      pcall(vim.cmd, "close")
      return nil
    end
    return bufnr
  else
    return set_buffer_in_window(bufnr_or_filepath, winnr)
  end
end

---Open buffer or file and return buffer number and window
---@param bufnr_or_filepath number|string
---@return number|nil bufnr, number|nil winnr
local function open_buffer_and_window(bufnr_or_filepath)
  local is_filepath = type(bufnr_or_filepath) == "string"

  if is_filepath then
    local filepath = bufnr_or_filepath --[[@as string]]
    local existing_bufnr = get_existing_buffer(filepath)

    if existing_bufnr then
      -- Case 1: Buffer exists and is visible
      local existing_win = ui.buf_get_win(existing_bufnr)
      if existing_win then
        return use_buffer_in_window(existing_bufnr, existing_win), existing_win
      end
      -- Case 2: Buffer exists but not visible
      local winnr = find_suitable_window()
      if winnr then
        local bufnr = set_buffer_in_window(existing_bufnr, winnr)
        return bufnr, winnr
      end
    else
      -- Case 3: Buffer doesn't exist
      local winnr = find_suitable_window()
      if winnr then
        local bufnr = create_buffer_in_window(filepath, winnr)
        return bufnr, winnr
      end
    end

    return create_split_window(filepath), api.nvim_get_current_win() -- Fallback
  else
    local bufnr = bufnr_or_filepath --[[@as number]]
    local existing_win = ui.buf_get_win(bufnr)

    if existing_win then
      return use_buffer_in_window(bufnr, existing_win), existing_win
    end
    local winnr = find_suitable_window()
    if winnr then
      local result_bufnr = set_buffer_in_window(bufnr, winnr)
      return result_bufnr, winnr
    end

    return create_split_window(bufnr), api.nvim_get_current_win() -- Fallback
  end
end

---Create a diff for a buffer or file and set up keymaps
---@param bufnr_or_filepath number|string The buffer number or file path to create diff for
---@param diff_id number|string Unique identifier for this diff
---@param opts? { original_content: string[], set_keymaps: boolean }
---@return table|nil diff The diff object, or nil if no diff was created
function M.create(bufnr_or_filepath, diff_id, opts)
  opts = opts or {}
  if opts.set_keymaps == nil then
    opts.set_keymaps = true
  end

  log:debug("[catalog::helpers::diff::create] Called - diff_id=%s", tostring(diff_id))

  if vim.g.codecompanion_auto_tool_mode or not config.display.diff.enabled then
    log:trace(
      "[catalog::helpers::diff::create] Skipping diff - auto_mode=%s, enabled=%s",
      tostring(vim.g.codecompanion_auto_tool_mode),
      tostring(config.display.diff.enabled)
    )
    return nil
  end

  local provider = config.display.diff.provider
  local ok, diff_module = pcall(require, "codecompanion.providers.diff." .. provider)
  if not ok then
    log:error("[catalog::helpers::diff::create] Failed to load provider '%s'", provider)
    return nil
  end

  local bufnr, winnr = open_buffer_and_window(bufnr_or_filepath)
  if not bufnr then
    log:warn("[catalog::helpers::diff::create] Failed to open buffer/file")
    return nil
  end

  if vim.bo[bufnr].buftype == "terminal" then
    log:debug("[catalog::helpers::diff::create] Skipping diff - terminal buffer")
    return nil
  end

  local diff = diff_module.new({
    bufnr = bufnr,
    -- Use provided content or fallback to current buffer content
    contents = opts.original_content or api.nvim_buf_get_lines(bufnr, 0, -1, true),
    filetype = api.nvim_get_option_value("filetype", { buf = bufnr }),
    id = diff_id,
    winnr = winnr,
  })

  if diff and opts.set_keymaps then
    vim.schedule(function()
      M.setup_keymaps(diff, opts)
    end)
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
