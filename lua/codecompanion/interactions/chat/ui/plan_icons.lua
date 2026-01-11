local api = vim.api
local config = require("codecompanion.config")

---@class CodeCompanion.Chat.UI.PlanIcons
local PlanIcons = {}

local CONSTANTS = {
  NS_PLAN_ICONS = api.nvim_create_namespace("CodeCompanion-plan_icons"),
  NS_PLAN_HIGHLIGHT = api.nvim_create_namespace("CodeCompanion-plan_highlight"),
  SIGN_GROUP = "codecompanion_plan",
  SIGN_NAME = "CodeCompanionPlan",
}

-- Define the sign for plan sections (only needs to be done once)
local sign_defined = false
local function ensure_sign_defined()
  if not sign_defined then
    local log = require("codecompanion.utils.log")
    log:debug("Defining CodeCompanionPlan sign")

    -- Get the configured sign character from config
    local sign_char = config.display.chat.icons.plan_sign or "▌"

    -- Sign options for visual grouping:
    -- "▎" - thin vertical bar (subtle, modern)
    -- "┃" - box drawing heavy vertical (bold, clear)
    -- "│" - box drawing light vertical (minimal)
    -- "▌" - left half block (medium weight) [default]
    -- "▐" - right half block (alternative)
    -- "║" - box drawing double vertical (decorative)
    
    vim.fn.sign_define(CONSTANTS.SIGN_NAME, {
      text = sign_char, -- Configurable sign character
      texthl = "CodeCompanionChatFold", -- Same as fold styling for consistency
      linehl = "", -- No line highlight (we use extmarks for that)
      numhl = "", -- No number column highlight
    })

    -- Verify sign was defined
    local defined = vim.fn.sign_getdefined(CONSTANTS.SIGN_NAME)
    log:debug("Sign defined: %s", vim.inspect(defined))

    sign_defined = true
  end
end

---Apply plan icon as overlay virtual text on the blank line before the plan header
---@param bufnr number
---@param line number 0-based line number
---@param opts table|nil Additional options
---@return number|nil The extmark id
function PlanIcons.apply(bufnr, line, opts)
  opts = vim.tbl_deep_extend("force", {
    priority = 100,
    virt_text_pos = "overlay",
  }, opts or {})

  local icon = config.display.chat.icons.plan or "󰸗  "
  local hl_group = "CodeCompanionChatPlan"

  return api.nvim_buf_set_extmark(bufnr, CONSTANTS.NS_PLAN_ICONS, line, 0, {
    virt_text = { { icon, hl_group } },
    virt_text_pos = opts.virt_text_pos,
    priority = opts.priority,
  })
end

---Clear a specific plan icon from buffer
---@param bufnr number
---@param extmark_id number
---@return nil
function PlanIcons:clear_icon(bufnr, extmark_id)
  if not extmark_id then
    return
  end
  api.nvim_buf_del_extmark(bufnr, CONSTANTS.NS_PLAN_ICONS, extmark_id)
end

---Clear all plan icons from buffer
---@param bufnr number
function PlanIcons.clear_icons(bufnr)
  api.nvim_buf_clear_namespace(bufnr, CONSTANTS.NS_PLAN_ICONS, 0, -1)
end

---Apply highlight to entire plan section
---@param bufnr number
---@param start_line number 0-based start line (inclusive)
---@param end_line number 0-based end line (inclusive)
---@return number|nil The extmark id
function PlanIcons.apply_highlight(bufnr, start_line, end_line)
  -- Clear any existing plan highlights first
  PlanIcons.clear_highlight(bufnr)

  -- Get the length of the last line to ensure we highlight it fully
  local last_line_text = vim.api.nvim_buf_get_lines(bufnr, end_line, end_line + 1, false)[1] or ""
  local end_col = #last_line_text

  -- Apply highlight extmark over the entire plan range
  -- Note: end_row is inclusive, end_col is exclusive in the API
  return api.nvim_buf_set_extmark(bufnr, CONSTANTS.NS_PLAN_HIGHLIGHT, start_line, 0, {
    end_row = end_line,
    end_col = end_col,
    hl_group = "CodeCompanionChatPlan",
    hl_eol = true, -- Extend highlight to end of screen line for empty lines
    priority = 90, -- Lower than icon priority (100) so icon renders on top
  })
end

---Clear all plan highlights from buffer
---@param bufnr number
function PlanIcons.clear_highlight(bufnr)
  api.nvim_buf_clear_namespace(bufnr, CONSTANTS.NS_PLAN_HIGHLIGHT, 0, -1)
end

---Apply sign column indicators to entire plan section
---@param bufnr number
---@param start_line number 0-based start line (inclusive)
---@param end_line number 0-based end line (inclusive)
function PlanIcons.apply_signs(bufnr, start_line, end_line)
  ensure_sign_defined()

  -- Ensure sign column is visible in all windows showing this buffer
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    vim.wo[winid].signcolumn = "yes"
  end

  -- Clear any existing plan signs first
  PlanIcons.clear_signs(bufnr)

  local log = require("codecompanion.utils.log")
  log:debug("Applying plan signs: bufnr=%d, start_line=%d, end_line=%d", bufnr, start_line, end_line)

  -- Debug: Show what's on each line we're about to place a sign on
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  log:debug("Buffer has %d total lines", total_lines)
  for line = start_line, end_line do
    local line_text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
    log:debug("  Line %d (1-based: %d): %q", line, line + 1, line_text)
  end

  -- Place signs on each line of the plan section
  -- Note: sign_place uses 1-based line numbers
  for line = start_line, end_line - 1 do
    local sign_id = vim.fn.sign_place(
      0, -- Let Vim assign the sign ID
      CONSTANTS.SIGN_GROUP,
      CONSTANTS.SIGN_NAME,
      bufnr,
      { lnum = line + 1, priority = 10 }
    )
    log:debug("Placed sign at line %d (1-based: %d), sign_id=%d", line, line + 1, sign_id)
  end

  -- Verify signs were placed
  local signs = vim.fn.sign_getplaced(bufnr, { group = CONSTANTS.SIGN_GROUP })
  log:debug("Signs placed: %s", vim.inspect(signs))
end

---Clear all plan signs from buffer
---@param bufnr number
function PlanIcons.clear_signs(bufnr)
  vim.fn.sign_unplace(CONSTANTS.SIGN_GROUP, { buffer = bufnr })
end

return PlanIcons
