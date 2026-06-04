local config = require("codecompanion.config")
local helpers = require("codecompanion.interactions.chat.helpers")
local log = require("codecompanion.utils.log")
local tokens = require("codecompanion.utils.tokens")

local M = {}

---@param chat CodeCompanion.Chat
---@return boolean
local function is_enabled(chat)
  local context_management = config.interactions.chat.opts.context_management
  if not context_management then
    return false
  end

  local enabled = context_management.enabled
  if type(enabled) == "function" then
    return enabled(chat.adapter)
  end

  return enabled == true
end

---Get the token count for the conversation
---@param messages CodeCompanion.Chat.Messages
---@return number
local function get_tokens(messages)
  for i = #messages, 1, -1 do
    local meta = messages[i]._meta
    if meta and meta.cumulative_tokens then
      local extra = 0
      for j = i + 1, #messages do
        extra = extra + ((messages[j]._meta and messages[j]._meta.estimated_tokens) or 0)
      end
      return meta.cumulative_tokens + extra
    end
  end

  return tokens.get_tokens(messages)
end

---Check token thresholds and run editing or compaction if needed
---@param chat CodeCompanion.Chat
---@return nil
function M.check(chat)
  if chat.adapter and chat.adapter.type == "acp" then
    return
  end
  if not is_enabled(chat) then
    return
  end
  if chat._compacting then
    return
  end
  if chat:has_orphaned_tool_calls() then
    return
  end

  local token_count = get_tokens(chat.messages)
  local ctx_mgmt_config = config.interactions.chat.opts.context_management

  local compaction_threshold = helpers.trigger_context_management(chat.adapter, { operation = "compaction" })
  if compaction_threshold > 0 and token_count >= compaction_threshold then
    local compaction = require("codecompanion.interactions.chat.context_management.compaction")
    compaction.compact(chat, {
      adapter = ctx_mgmt_config.compaction.adapter,
      fallback_to_chat_adapter = ctx_mgmt_config.compaction.fallback_to_chat_adapter,
      min_token_savings = ctx_mgmt_config.compaction.min_token_savings,
    })
    return
  end

  local editing_threshold = helpers.trigger_context_management(chat.adapter, { operation = "editing" })
  if editing_threshold > 0 and token_count >= editing_threshold then
    local editing = require("codecompanion.interactions.chat.context_management.editing")
    local _, cleared = editing.apply(chat.messages, {
      current_cycle = chat.cycle,
      exclude_tools = ctx_mgmt_config.editing.exclude_tools,
      keep_cycles = ctx_mgmt_config.editing.keep_cycles,
    })
    if cleared > 0 then
      log:info("[Context Management] Edited %d tool result(s)", cleared)
    end
  end
end

return M
