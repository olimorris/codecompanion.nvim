local BaseFormatter = require("codecompanion.interactions.chat.ui.formatters.base")

---@class CodeCompanion.Chat.UI.Formatters.Plan : CodeCompanion.Chat.UI.Formatters.Base
local Plan = setmetatable({}, { __index = BaseFormatter })
Plan.__class = "Plan"

function Plan:can_handle(message, opts, tags)
  return opts and opts.type == tags.PLAN_MESSAGE
end

function Plan:get_type()
  return self.chat.MESSAGE_TYPES.PLAN_MESSAGE
end

function Plan:format(message, opts, state)
  local lines = {}

  if state.is_new_block and state.block_index > 0 then
    table.insert(lines, "")
    table.insert(lines, "")
  end

  if not state.has_plan_output then
    table.insert(lines, "### Plan")
    table.insert(lines, "")
    state:mark_plan_started()
  end

  local content_start = #lines
  for _, line in ipairs(vim.split(message.content, "\n", { plain = true, trimempty = false })) do
    table.insert(lines, line)
  end

  if opts._plan_entries then
    local plan_icons = {}
    for i, entry in ipairs(opts._plan_entries) do
      table.insert(plan_icons, {
        line_offset = content_start + (i - 1),
        status = entry.status or "pending",
      })
    end
    opts._plan_icons = plan_icons
  end

  return lines, nil
end

return Plan
