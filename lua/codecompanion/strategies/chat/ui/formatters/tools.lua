local BaseFormatter = require("codecompanion.strategies.chat.ui.formatters.base")

---@class CodeCompanion.Chat.UI.Formatters.Tools : CodeCompanion.Chat.UI.Formatters.Base
---@field chat CodeCompanion.Chat
local Tools = BaseFormatter:new(chat)
Tools.__class = "Tools"

function Tools:can_handle(data, opts)
  return opts and opts.tag == self.chat.MESSAGE_TAGS.TOOL_OUTPUT
end

function Tools:get_tag()
  return self.chat.MESSAGE_TAGS.TOOL_OUTPUT
end

function Tools:format(data, opts)
  local lines = {}

  -- Add spacing based on previous content
  if self.chat._last_tag == self.chat.MESSAGE_TAGS.LLM_MESSAGE then
    table.insert(lines, "")
    table.insert(lines, "")
  end

  -- Write the tool content
  local content_start = #lines + 1
  local content = data.content or ""
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
