local config = require("codecompanion.config")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local ui_utils = require("codecompanion.utils.ui")

local api = vim.api

local M = {}

-- Banner constants and highlights
M.CONSTANTS = {
  ICON = " ",
  SEP = "  •  ",
  COMPACT_SEP = " • ",
  HIGHLIGHT_KEYMAP = "CodeCompanionBannerKeymap",
  HIGHLIGHT_COUNT = "CodeCompanionNumber",
  MIN_WIDTH = 60,
}

---Build hunk navigation section
---@param diff table|nil Diff object with hunk_count
---@param km table|nil Keymap configuration
---@param mode? string Keymap mode (default: "n")
---@return string nav Navigation section string, or empty string if no hunks
function M.build_hunk_nav(diff, km, mode)
  mode = mode or "n"

  if not diff or not diff.hunk_count or diff.hunk_count == 0 then
    return ""
  end

  if not km then
    return ""
  end

  local next_h = (km.next_hunk and km.next_hunk.modes[mode]) or "]h"
  local prev_h = (km.prev_hunk and km.prev_hunk.modes[mode]) or "[h"

  return string.format("Hunk nav: %s/%s (%%#%s#%s%%*)", next_h, prev_h, M.CONSTANTS.HIGHLIGHT_COUNT, diff.hunk_count)
end

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
  local cfg = api.nvim_win_get_config(win_id)
  -- Return false if it's floating (we want non-floating windows)
  return not ((cfg.relative ~= "" and cfg.relative ~= nil) or cfg.external == true)
end

---Check if buffer exists for a file path
---@param path string
---@return number|nil bufnr Buffer number if exists, nil otherwise
local function get_existing_buffer(path)
  local bufnr = vim.fn.bufnr(path)
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
  pcall(api.nvim_set_current_win, winnr)

  return bufnr
end

---Set existing buffer in a window
---@param bufnr number
---@param winnr number
---@return number|nil bufnr
local function set_buffer_in_window(bufnr, winnr)
  local ok = pcall(api.nvim_win_set_buf, winnr, bufnr)
  if ok then
    pcall(api.nvim_set_current_win, winnr)
    return bufnr
  end

  return nil
end

---Create new buffer from file in window
---@param path string
---@param winnr number
---@return number|nil bufnr
local function create_buffer_in_window(path, winnr)
  if not vim.uv.fs_stat(vim.fs.normalize(path)) then
    log:debug("[catalog::helpers::diff::create] File not readable: %s", path)
    return nil
  end

  local ok = pcall(api.nvim_win_call, winnr, function()
    vim.cmd.edit(vim.fn.fnameescape(path))
    vim.schedule(function()
      pcall(api.nvim_set_current_win, winnr)
    end)
  end)

  if ok then
    return api.nvim_win_get_buf(winnr)
  end

  log:warn("[catalog::helpers::diff::create] Failed to create buffer for: %s", path)
  return nil
end

---Create new split window with buffer
---@param bufnr_or_path number|string
---@return number|nil bufnr
local function create_split_window(bufnr_or_path)
  vim.cmd("topleft vnew")
  local winnr = api.nvim_get_current_win()

  if type(bufnr_or_path) == "string" then
    local bufnr = create_buffer_in_window(bufnr_or_path, winnr)
    if not bufnr then
      pcall(vim.cmd, "close")
      return nil
    end
    return bufnr
  else
    return set_buffer_in_window(bufnr_or_path, winnr)
  end
end

---Setup winbar for diff window with keymap hints
---@param winnr number Window number to set up winbar for
---@param diff? table Optional diff object to show hunk count and navigation
---@return nil
local function place_diff_winbar(winnr, diff)
  local provider = config.display.diff.provider
  local provider_config = config.display.diff.provider_opts[provider] or {}
  local show_keymap_hints = provider_config.opts and provider_config.opts.show_keymap_hints
  if not show_keymap_hints then
    return
  end

  local km = config.strategies.inline.keymaps
  if not km then
    return
  end

  local mode = "n"
  local ga = km.always_accept and km.always_accept.modes[mode] or nil
  local gy = km.accept_change and km.accept_change.modes[mode] or nil
  local gn = km.reject_change and km.reject_change.modes[mode] or nil

  if not (ga or gy or gn) then
    return
  end

  -- Build review section with highlighted keymaps
  local review_parts = {}
  if ga then
    table.insert(review_parts, "[%#" .. M.CONSTANTS.HIGHLIGHT_KEYMAP .. "#" .. ga .. "%*: Always Accept]")
  end
  if gy then
    table.insert(review_parts, "[%#" .. M.CONSTANTS.HIGHLIGHT_KEYMAP .. "#" .. gy .. "%*: Accept]")
  end
  if gn then
    table.insert(review_parts, "[%#" .. M.CONSTANTS.HIGHLIGHT_KEYMAP .. "#" .. gn .. "%*: Reject]")
  end
  local review = M.CONSTANTS.ICON .. M.CONSTANTS.SEP .. table.concat(review_parts, "  ")

  local nav = M.build_hunk_nav(diff, km, mode)
  local banner = nav ~= "" and (review .. M.CONSTANTS.SEP .. nav) or review

  -- Truncate if window too small
  local ok, win_width = pcall(api.nvim_win_get_width, winnr)
  if ok and win_width < M.CONSTANTS.MIN_WIDTH then
    local short_keys = table.concat(
      vim.tbl_filter(function(x)
        return x
      end, {
        ga and (ga .. ":Always Accept"),
        gy and (gy .. ":Accept"),
        gn and (gn .. ":Reject"),
      }),
      " "
    )
    if nav ~= "" then
      banner = M.CONSTANTS.ICON .. " " .. short_keys .. M.CONSTANTS.COMPACT_SEP .. nav:gsub("Hunk nav: ", "")
    else
      banner = M.CONSTANTS.ICON .. " " .. short_keys
    end
  end

  ui_utils.set_winbar(winnr, banner, "CodeCompanionChatInfoBanner", false)
end

---Create diff floating window using create_float
---@param bufnr number Buffer to display in the floating window
---@param path string|nil Optional path for window title
---@return number? winnr Window number of the created floating window
local function create_diff_floating_window(bufnr, path)
  local window_config = vim.tbl_deep_extend("force", config.display.chat.child_window, config.display.chat.diff_window)

  local provider = config.display.diff.provider
  local provider_config = config.display.diff.provider_opts[provider] or {}
  local show_dim = provider_config.opts and provider_config.opts.show_dim

  local filetype = api.nvim_get_option_value("filetype", { buf = bufnr })
  local content = {} -- Dummy content for create_float function

  local _, winnr = ui_utils.create_float(content, {
    bufnr = bufnr,
    set_content = false, -- Don't overwrite existing buffer content
    window = { width = window_config.width, height = window_config.height },
    row = window_config.row,
    col = window_config.col,
    relative = window_config.relative,
    filetype = filetype,
    title = ui_utils.build_float_title({
      title_prefix = " Diff Review ",
      path = path,
    }),
    lock = false, -- Allow edits for diff
    ignore_keymaps = true,
    opts = window_config.opts,
    show_dim = show_dim,
  })

  return winnr
end

---Create floating window only (no buffer creation)
---@param bufnr number Buffer number to display in the floating window
---@param path string|nil Optional path for window title
---@return number|nil winnr Window number of the floating window
local function create_floating_window_only(bufnr, path)
  local display_path = path
  if not display_path and bufnr and api.nvim_buf_is_valid(bufnr) then
    local buf_name = api.nvim_buf_get_name(bufnr)
    if buf_name and buf_name ~= "" then
      display_path = buf_name
    end
  end

  return create_diff_floating_window(bufnr, display_path)
end

---Open buffer or file and return buffer number and window
---@param bufnr_or_path number|string
---@return number|nil bufnr, number|nil winnr
local function open_buffer_and_window(bufnr_or_path)
  local provider = config.display.diff.provider
  local provider_config = config.display.diff.provider_opts[provider] or {}
  local layout = provider_config.layout
  local is_path = type(bufnr_or_path) == "string"
  local bufnr

  -- First, get or create the buffer
  if is_path then
    local path = bufnr_or_path --[[@as string]]
    local existing_bufnr = get_existing_buffer(path)
    if existing_bufnr then
      bufnr = existing_bufnr
    else
      if not vim.uv.fs_stat(vim.fs.normalize(path)) then
        log:debug("[catalog::helpers::diff::create] File not readable: %s", path)
        return nil, nil
      end
      bufnr = vim.fn.bufnr(path, true)
      api.nvim_buf_call(bufnr, function()
        vim.cmd("silent edit " .. vim.fn.fnameescape(path))
      end)
    end
  else
    bufnr = bufnr_or_path --[[@as number]]
  end

  if not api.nvim_buf_is_valid(bufnr) then
    log:debug("[catalog::helpers::diff::create] Invalid buffer")
    return nil, nil
  end

  -- Now handle window creation based on layout
  if layout == "float" then
    local path = is_path and bufnr_or_path or nil --[[@as string]]
    local winnr = create_floating_window_only(bufnr, path)
    if winnr then
      return bufnr, winnr
    end
    return nil, nil
  end

  if is_path then
    local path = bufnr_or_path --[[@as string]]
    local existing_bufnr = get_existing_buffer(path)

    if existing_bufnr then
      -- Case 1: Buffer exists and is visible
      local existing_win = ui_utils.buf_get_win(existing_bufnr)
      if existing_win then
        return use_buffer_in_window(existing_bufnr, existing_win), existing_win
      end
      -- Case 2: Buffer exists but not visible
      local winnr = find_suitable_window()
      if winnr then
        local result_bufnr = set_buffer_in_window(existing_bufnr, winnr)
        return result_bufnr, winnr
      end
    else
      -- Case 3: Buffer doesn't exist
      local winnr = find_suitable_window()
      if winnr then
        local result_bufnr = create_buffer_in_window(path, winnr)
        return result_bufnr, winnr
      end
    end

    return create_split_window(path), api.nvim_get_current_win() -- Fallback
  else
    local existing_win = ui_utils.buf_get_win(bufnr)

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
---@param bufnr_or_path number|string The buffer number or file path to create diff for
---@param diff_id number|string Unique identifier for this diff
---@param opts? { original_content: string[], set_keymaps?: boolean }
---@return table|nil diff The diff object, or nil if no diff was created
function M.create(bufnr_or_path, diff_id, opts)
  opts = opts or {}
  if opts.set_keymaps == nil then
    opts.set_keymaps = true
  end

  log:debug("[catalog::helpers::diff::create] Called - diff_id=%s", tostring(diff_id))

  if vim.g.codecompanion_yolo_mode or not config.display.diff.enabled then
    return nil
  end

  local provider = config.display.diff.provider
  local ok, diff_module = pcall(require, "codecompanion.providers.diff." .. provider)
  if not ok then
    log:error("[catalog::helpers::diff::create] Failed to load provider '%s'", provider)
    return nil
  end

  local bufnr, winnr = open_buffer_and_window(bufnr_or_path)
  if not bufnr then
    log:warn("[catalog::helpers::diff::create] Failed to open buffer/file")
    return nil
  end

  if vim.bo[bufnr].buftype == "terminal" then
    log:debug("[catalog::helpers::diff::create] Skipping diff - terminal buffer")
    return nil
  end

  local provider = config.display.diff.provider
  local provider_config = config.display.diff.provider_opts[provider] or {}
  local layout = provider_config.layout

  local diff_args = {
    bufnr = bufnr,
    -- Use provided content or fallback to current buffer content
    contents = opts.original_content or api.nvim_buf_get_lines(bufnr, 0, -1, true),
    filetype = api.nvim_get_option_value("filetype", { buf = bufnr }),
    id = diff_id,
    winnr = winnr,
    is_floating = layout == "float",
  }

  local diff = diff_module.new(diff_args)

  if diff and opts.set_keymaps then
    vim.schedule(function()
      M.setup_keymaps(diff, opts)
      if winnr and api.nvim_win_is_valid(winnr) then
        place_diff_winbar(winnr, diff)
      end
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
  if vim.g.codecompanion_yolo_mode then
    return false, "yolo_mode"
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
