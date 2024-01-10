local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

---@param prompts table
---@param context table
local function modal_prompts(prompts, context)
  local messages = {}
  for _, prompt in ipairs(prompts) do
    --TODO: These nested conditionals suck. Refactor soon
    if not prompt.contains_code or (prompt.contains_code and config.options.send_code) then
      if not prompt.condition or (prompt.condition and prompt.condition(context)) then
        local content
        if type(prompt.content) == "function" then
          content = prompt.content(context)
        else
          content = prompt.content
        end

        table.insert(messages, {
          role = prompt.role,
          content = content,
        })
      end
    end
  end

  return messages
end

---@class CodeCompanion.Strategy
---@field client CodeCompanion.Client
---@field context table
---@field selected table
local Strategy = {}

---@class CodeCompanion.StrategyArgs
---@field client CodeCompanion.Client
---@field context table
---@field selected table

---@param args CodeCompanion.StrategyArgs
---@return CodeCompanion.Strategy
function Strategy.new(args)
  return setmetatable({
    client = args.client,
    context = args.context,
    selected = args.selected,
  }, { __index = Strategy })
end

function Strategy:start(strategy)
  return self[strategy](self)
end

---@return CodeCompanion.Chat
function Strategy:chat()
  local messages
  local mode = self.context.mode:lower()
  local prompts = self.selected.prompts

  if type(prompts[mode]) == "function" then
    return prompts[mode]()
  elseif type(prompts[mode]) == "table" then
    messages = modal_prompts(prompts[mode], self.context)
  else
    -- No mode specified
    messages = modal_prompts(prompts, self.context)
  end

  return require("codecompanion.strategy.chat").new({
    client = self.client,
    messages = messages,
    show_buffer = true,
  })
end

function Strategy:advisor()
  return require("codecompanion.strategy.advisor")
    .new({
      context = self.context,
      client = self.client,
      opts = self.selected.opts,
      prompts = self.selected.prompts,
    })
    :start()
end

function Strategy:author()
  return require("codecompanion.strategy.author")
    .new({
      context = self.context,
      client = self.client,
      opts = self.selected.opts,
      prompts = self.selected.prompts,
    })
    :start()
end

function Strategy:conversations()
  local conversation = require("codecompanion.strategy.conversation")
  local items = conversation:list({ sort = true })

  local columns = {
    "tokens",
    "filename",
    "dir",
  }

  require("codecompanion.utils.ui").selector(items, {
    prompt = "Converations",
    format = function(item)
      local formatted_item = {}
      for _, column in ipairs(columns) do
        table.insert(formatted_item, item[column] or "")
      end
      return formatted_item
    end,
    callback = function(selected)
      return conversation
        .new({
          filename = selected.filename,
        })
        :load(self.client, selected)
    end,
  })
end

return Strategy
