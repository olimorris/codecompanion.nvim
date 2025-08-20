local BaseFormatter = require("codecompanion.strategies.chat.ui.formatters.base")
local config = require("codecompanion.config")

local CONSTANTS = {
  icons = {
    in_progress = config.display.chat.icons.tool_in_progress or "⚡",
    failed = config.display.chat.icons.tool_failure or "❌",
    completed = config.display.chat.icons.tool_success or "✅",
  },
}

---@class CodeCompanion.Chat.UI.Formatters.Tools : CodeCompanion.Chat.UI.Formatters.Base
local Tools = setmetatable({}, { __index = BaseFormatter })
Tools.__class = "Tools"

function Tools:can_handle(message, opts, tags)
  return opts and opts.type == tags.TOOL_MESSAGE
end

function Tools:get_type()
  return self.chat.MESSAGE_TYPES.TOOL_MESSAGE
end

function Tools:format(message, opts, state)
  local lines = {}
  local content_line_offset = 0

  if state.has_reasoning_output then
    state:mark_reasoning_complete()
    table.insert(lines, "")
    table.insert(lines, "")
    table.insert(lines, "### Response")
    content_line_offset = 3
  end

  if state.is_new_section then
    table.insert(lines, "")
    content_line_offset = content_line_offset + 1
  end

  -- Simple content formatting with status icons
  local content = message.content or ""
  if opts.status then
    local icon = CONSTANTS.icons[opts.status]
    content = icon .. " " .. content
    opts._icon_info = {
      status = opts.status,
      has_icon = true,
      line_offset = content_line_offset,
    }
  end

  local content_start = #lines + 1
  for _, line in ipairs(vim.split(content, "\n", { plain = true, trimempty = false })) do
    table.insert(lines, line)
  end
  table.insert(lines, "")

  -- If there's a status being passed then we know it's an ACP tool and we can
  -- prevent any folds from being created
  if not config.strategies.chat.tools.opts.folds.enabled or opts.status then
    return lines, nil
  end

  -- Folds can only work up to the penultimate line in the buffer, so an extra
  -- line has been added as a result. But, we don't want to fold this line
  local content_end = #lines - 1

  local fold_info = nil
  if content_end >= content_start then
    fold_info = {
      start_offset = content_start - 1, -- 0-based index
      end_offset = content_end - 1, -- 0-based index
      first_line = lines[content_start] or "",
    }
  end

  return lines, fold_info
end

return Tools
