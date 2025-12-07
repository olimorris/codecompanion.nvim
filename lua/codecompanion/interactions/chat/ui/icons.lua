local api = vim.api
local config = require("codecompanion.config")

---@class CodeCompanion.Chat.UI.Icons
local Icons = {}

local CONSTANTS = {
  NS_TOOL_ICONS = api.nvim_create_namespace("CodeCompanion-tool_icons"),
}

---Apply colored icon overlay at column 0
---@param bufnr number
---@param line number 0-based line number
---@param status string The tool status (in_progress, completed, failed)
---@param opts table|nil Additional options
---@return number|nil The extmark id or nil if status is invalid
function Icons.apply(bufnr, line, status, opts)
  opts = vim.tbl_deep_extend("force", {
    priority = 100,
    virt_text_pos = "overlay",
  }, opts or {})

  local icon_configs = {
    pending = {
      icon = config.display.chat.icons.tool_pending or "⚡",
      hl_group = "CodeCompanionChatToolPending",
    },
    in_progress = {
      icon = config.display.chat.icons.tool_in_progress or "⚡",
      hl_group = "CodeCompanionChatToolInProgress",
    },
    completed = {
      icon = config.display.chat.icons.tool_success or "✅",
      hl_group = "CodeCompanionChatToolSuccessIcon",
    },
    failed = {
      icon = config.display.chat.icons.tool_failure or "❌",
      hl_group = "CodeCompanionChatToolFailureIcon",
    },
  }

  local config_entry = icon_configs[status]
  if not config_entry then
    return
  end

  return api.nvim_buf_set_extmark(bufnr, CONSTANTS.NS_TOOL_ICONS, line, 0, {
    virt_text = { { config_entry.icon, config_entry.hl_group } },
    virt_text_pos = opts.virt_text_pos,
    priority = opts.priority,
  })
end

---Clear a specific tool icon from buffer
---@param bufnr number
---@param extmark_id number
---@return nil
function Icons:clear_icon(bufnr, extmark_id)
  if not extmark_id then
    return
  end
  api.nvim_buf_del_extmark(bufnr, CONSTANTS.NS_TOOL_ICONS, extmark_id)
end

---Clear all tool icons from buffer
---@param bufnr number
function Icons.clear_icons(bufnr)
  api.nvim_buf_clear_namespace(bufnr, CONSTANTS.NS_TOOL_ICONS, 0, -1)
end

return Icons
