local BaseFormatter = require("codecompanion.interactions.chat.ui.formatters.base")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.Chat.UI.Formatters.Plan : CodeCompanion.Chat.UI.Formatters.Base
local Plan = setmetatable({}, { __index = BaseFormatter })
Plan.__class = "Plan"

function Plan:can_handle(message, opts, tags)
  return opts and opts.type == tags.PLAN_MESSAGE
end

function Plan:get_type(opts)
  return self.chat.MESSAGE_TYPES.PLAN_MESSAGE
end

function Plan:format(message, opts, state)
  local lines = {}
  local content_line_offset = 0

  -- Add spacing if needed (following standard formatter pattern)
  if state.is_new_block and state.block_index > 0 then
    table.insert(lines, "")
    content_line_offset = 1
  end

  -- Add a blank line at the start of the plan block for the icon
  table.insert(lines, "")
  local icon_line_offset = content_line_offset
  content_line_offset = content_line_offset + 1

  local content = message.content or ""

  -- Split content into lines but DO NOT prepend icon text
  -- Keep buffer content as pure markdown so treesitter can parse it
  local content_lines = vim.split(content, "\n", { plain = true, trimempty = false })

  -- Set icon info so Builder applies the icon on the blank line before the header
  opts._icon_info = {
    has_icon = true,
    line_offset = icon_line_offset, -- Icon goes on blank line before content
  }

  for _, line in ipairs(content_lines) do
    table.insert(lines, line)
  end

  return lines, nil
end

return Plan
