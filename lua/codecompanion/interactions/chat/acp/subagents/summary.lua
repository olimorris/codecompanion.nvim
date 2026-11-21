local tool_calls = require("codecompanion.interactions.chat.ui.tool_calls")

local fmt = string.format

local FAILED_STOP_REASONS = { error = true, refusal = true, cancelled = true }

local M = {}

---@param subagent CodeCompanion.Chat.ACPSubagent
---@return string
function M.get_label(subagent)
  return subagent.info.title or subagent.info.description or "Subagent"
end

---Read a subagent's work state as a tool call status, and as a description for its float
---@param subagent CodeCompanion.Chat.ACPSubagent
---@return { status: string, description: string }
function M.get_state(subagent)
  if subagent.disconnected then
    return { status = "pending", description = "Disconnected" }
  end
  local state = subagent.info.state
  if type(state) ~= "table" then
    return { status = "pending", description = "Unconfirmed" }
  end

  local parts = { state.state }
  if type(state.stopReason) == "string" then
    table.insert(parts, fmt("(%s)", state.stopReason))
  end
  if type(state.error) == "table" and state.error.message then
    table.insert(parts, fmt("- %s", state.error.message))
  end

  local status = "pending"
  if state.state == "running" then
    status = "in_progress"
  elseif state.state == "idle" then
    status = FAILED_STOP_REASONS[state.stopReason] and "failed" or "completed"
  end
  return { status = status, description = table.concat(parts, " ") }
end

---Write the subagent's summary line, or rewrite it when its title or state changed
---@param chat CodeCompanion.Chat
---@param subagent CodeCompanion.Chat.ACPSubagent
---@return nil
function M.render(chat, subagent)
  local summary =
    tool_calls.format_summary({ kind = "subagent", detail = M.get_label(subagent), tag = subagent.model }).text
  local status = M.get_state(subagent).status

  local ui = subagent.ui
  if ui and ui.summary == summary and ui.status == status then
    return
  end

  if ui and ui.line_number then
    local ok, update = pcall(tool_calls.update, chat, {
      icon_id = ui.icon_id,
      line_number = ui.line_number,
      status = status,
      summary = summary,
    })
    if ok and update.is_updated then
      ui.icon_id = update.icon_id or ui.icon_id
      ui.summary = summary
      ui.status = status
      return
    end
  end

  subagent.ui = tool_calls.write(chat, { call_id = subagent.info.id, status = status, summary = summary })
  subagent.ui.summary = summary
  subagent.ui.status = status
end

return M
