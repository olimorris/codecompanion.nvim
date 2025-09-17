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
function Icons.apply_tool_icon(bufnr, line, status)
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

  api.nvim_buf_set_extmark(bufnr, CONSTANTS.NS_TOOL_ICONS, line, 0, {
    virt_text = { { config_entry.icon, config_entry.hl_group } },
    virt_text_pos = "overlay",
    priority = 100,
  })
end

---Clear all tool icons from buffer
---@param bufnr number
function Icons.clear_tool_icons(bufnr)
  api.nvim_buf_clear_namespace(bufnr, CONSTANTS.NS_TOOL_ICONS, 0, -1)
end

return Icons
