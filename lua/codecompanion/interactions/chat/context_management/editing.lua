--=============================================================================
-- Context Editing
--
-- Replaces aged messages in the chat buffer to reduce the token count. This
-- is done by mutating the message object, in-place.
--
-- Currently, only tool results are edited.
--
-- Sources:
-- https://platform.claude.com/docs/en/build-with-claude/context-editing
--=============================================================================

local tokens = require("codecompanion.utils.tokens")

local M = {}

M.PLACEHOLDERS = {
  tool_result = "<important>Tool result cleared to save context. Re-run the tool if you need this output</important>",
}

---@class CodeCompanion.Chat.ContextManagement.Editing.Opts
---@field current_cycle integer The cycle the chat buffer is currently on
---@field exclude_tools? string[] Tool names whose results are never edited
---@field keep_cycles integer Preserve tool results from the most recent N cycles

---Builds a map of tool call_id to tool name
---@param messages CodeCompanion.Chat.Messages
---@return table<string, string>
local function map_tool_calls(messages)
  local map = {}
  for _, msg in ipairs(messages) do
    if msg.tools and msg.tools.calls then
      for _, call in ipairs(msg.tools.calls) do
        local fn = call["function"]
        if call.id and fn and fn.name then
          map[call.id] = fn.name
        end
      end
    end
  end
  return map
end

---Edit tool result messages older than the keep_cycles window
---@param messages CodeCompanion.Chat.Messages
---@param opts CodeCompanion.Chat.ContextManagement.Editing.Opts
---@return number Number of messages cleared
local function tool_results(messages, opts)
  local exclude = {}
  for _, name in ipairs(opts.exclude_tools or {}) do
    exclude[name] = true
  end

  local tool_names = map_tool_calls(messages)
  local cutoff = opts.current_cycle - opts.keep_cycles
  local placeholder = M.PLACEHOLDERS.tool_result
  local cleared = 0

  for _, msg in ipairs(messages) do
    local is_tool_result = msg.role == "tool" and msg.tools and msg.tools.call_id
    if is_tool_result then
      local context_management = msg._meta and msg._meta.context_management
      local already_edited = context_management and context_management.edited
      local cycle = msg._meta and msg._meta.cycle
      local tool_name = tool_names[msg.tools.call_id]
      local excluded = tool_name and exclude[tool_name]

      if not already_edited and not excluded and cycle and cycle <= cutoff then
        msg.content = placeholder
        msg._meta.estimated_tokens = tokens.calculate(placeholder)
        msg._meta.context_management = msg._meta.context_management or {}
        msg._meta.context_management.edited = true
        cleared = cleared + 1
      end
    end
  end

  return cleared
end

---Replace aged messages
---@param messages CodeCompanion.Chat.Messages
---@param opts CodeCompanion.Chat.ContextManagement.Editing.Opts
---@return CodeCompanion.Chat.Messages messages
---@return number Number of messages cleared
function M.apply(messages, opts)
  local cleared = tool_results(messages, opts)
  return messages, cleared
end

return M
