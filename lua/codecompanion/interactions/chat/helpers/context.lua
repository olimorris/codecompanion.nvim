local config = require("codecompanion.config")

local tags = require("codecompanion.interactions.shared.tags")
local tokens = require("codecompanion.utils.tokens")

local M = {}

local fmt = string.format

---@param messages CodeCompanion.Chat.Messages
---@return number
function M.estimate_tokens(messages)
  local count = 0
  for _, message in ipairs(messages) do
    local meta = message._meta or {}
    if meta.tag ~= tags.IMAGE then
      count = count + (meta.estimated_tokens or tokens.calculate(message.content))
    end
  end

  return count
end

---@param opts { adapter: CodeCompanion.HTTPAdapter, messages: CodeCompanion.Chat.Messages }
---@return { exceeded: boolean, token_count?: number, input_limit?: number }
function M.exceeds_input_limit(opts)
  local shared = require("codecompanion.adapters.shared")
  if shared.manages_own_context(opts.adapter) then
    return { exceeded = false }
  end

  local input_limit = shared.input_limit(opts.adapter)
  if not input_limit then
    return { exceeded = false }
  end

  local token_count = M.estimate_tokens(opts.messages)

  return { exceeded = token_count >= input_limit, token_count = token_count, input_limit = input_limit }
end

---The most tokens a single tool result may contribute to the message history
---@param adapter CodeCompanion.HTTPAdapter
---@return number
local function tool_output_limit(adapter)
  local limit = config.interactions.chat.tools.opts.max_output_tokens
  local input_limit = require("codecompanion.adapters.shared").input_limit(adapter)

  return input_limit and math.min(limit, input_limit) or limit
end

---@param opts { adapter: CodeCompanion.HTTPAdapter, content: string }
---@return string
function M.truncate_tool_output(opts)
  if type(opts.content) ~= "string" or opts.content == "" then
    return opts.content
  end

  local token_count = tokens.calculate(opts.content)
  local limit = tool_output_limit(opts.adapter)
  if token_count <= limit then
    return opts.content
  end

  local notice = fmt(
    "\n\n[Tool output truncated: it was around %d tokens, which is over the %d token limit for a single tool result. Re-run the tool with a narrower scope to see the rest.]",
    token_count,
    limit
  )

  -- The notice has to fit inside the limit too, otherwise trimming puts us back over it
  local budget = math.max(limit - tokens.calculate(notice), 0)
  local keep = math.floor(#opts.content * (budget / token_count))

  return opts.content:sub(1, keep) .. notice
end

return M
