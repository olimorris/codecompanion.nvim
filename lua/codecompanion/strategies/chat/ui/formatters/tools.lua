local BaseFormatter = require("codecompanion.strategies.chat.ui.formatters.base")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local CONSTANTS = {
  icons = {
    pending = config.display.chat.icons.tool_pending or "⏳",
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

function Tools:get_type(opts)
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

  if state.last_type == self.chat.MESSAGE_TYPES.TOOL_MESSAGE then
    table.insert(lines, "")
    content_line_offset = 1
  end

  if state.is_new_block then
    if state.block_index > 0 then
      table.insert(lines, "")
      table.insert(lines, "")
      content_line_offset = content_line_offset + 2
    else
      table.insert(lines, "")
      content_line_offset = content_line_offset + 1
    end
  end

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

  local content_start_index = #lines + 1
  local content_lines = vim.split(content, "\n", { plain = true, trimempty = false })
  for _, line in ipairs(content_lines) do
    table.insert(lines, line)
  end

  -- If there's a status being passed then we know it's an ACP tool and we can
  -- prevent any folds from being created
  if not config.strategies.chat.tools.opts.folds.enabled or opts.status then
    return lines, nil
  end

  -- Calculate fold positions relative to the buffer
  local fold_info = nil
  if #content_lines > 1 then
    fold_info = {
      start_offset = content_start_index - 1, -- 0-based: first content line
      end_offset = content_start_index + #content_lines - 2, -- 0-based: last content line
      first_line = content_lines[1] or "",
    }
  end

  return lines, fold_info
end

return Tools
