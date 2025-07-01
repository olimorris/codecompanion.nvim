local BaseFormatter = require("codecompanion.strategies.chat.ui.formatters.base")
local log = require("codecompanion.utils.log")

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

  if state.is_new_section then
    table.insert(lines, "")
  end
  if state.last_type == self.chat.MESSAGE_TYPES.LLM_MESSAGE then
    log:debug("Last tag was LLM_MESSAGE, adding extra spacing")
    table.insert(lines, "")
  end

  -- Write the tool content
  local content_start = #lines + 1
  local content = message.content or ""
  for _, line in ipairs(vim.split(content, "\n", { plain = true, trimempty = false })) do
    table.insert(lines, line)
  end
  local content_end = #lines

  -- Calculate fold info if multi-line
  local fold_info = nil
  if content_end > content_start then
    fold_info = {
      start_offset = content_start - 1,
      end_offset = content_end - 1,
      first_line = lines[content_start] or "",
    }
  end

  return lines, fold_info
end

return Tools
