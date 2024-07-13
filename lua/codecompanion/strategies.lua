local config = require("codecompanion").config

local log = require("codecompanion.utils.log")

---@param prompts table
---@param context table
local function process_prompts(prompts, context)
  local messages = {}
  for _, prompt in ipairs(prompts) do
    if prompt.condition then
      if not prompt.condition(context) then
        goto continue
      end
    end

    --TODO: These nested conditionals suck. Refactor soon
    if not prompt.contains_code or (prompt.contains_code and config.opts.send_code) then
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
    ::continue::
  end

  return messages
end

---@class CodeCompanion.Strategies
---@field context table
---@field selected table
local Strategies = {}

---@class CodeCompanion.StrategyArgs
---@field context table
---@field selected table

---@param args CodeCompanion.StrategyArgs
---@return CodeCompanion.Strategies
function Strategies.new(args)
  log:trace("Context: %s", args.context)

  return setmetatable({
    context = args.context,
    selected = args.selected,
  }, { __index = Strategies })
end

function Strategies:start(strategy)
  return self[strategy](self)
end

---@return nil|CodeCompanion.Chat
function Strategies:chat()
  local messages
  local mode = self.context.mode:lower()
  local prompts = self.selected.prompts

  if type(prompts[mode]) == "function" then
    return prompts[mode]()
  elseif type(prompts[mode]) == "table" then
    messages = process_prompts(prompts[mode], self.context)
  else
    -- No mode specified
    messages = process_prompts(prompts, self.context)
  end

  if not messages or #messages == 0 then
    vim.notify("[CodeCompanion.nvim]\nThere are no messages to prompt the LLM", vim.log.levels.WARN)
    return
  end

  local function chat(input)
    if input then
      table.insert(messages, {
        role = "user",
        content = input,
      })
    end

    log:trace("Strategy: Chat")
    return require("codecompanion.strategies.chat").new({
      type = self.selected.type,
      adapter = self.selected.adapter,
      context = self.context,
      messages = messages,
      auto_submit = (self.selected.opts and self.selected.opts.auto_submit) or false,
      stop_context_insertion = (self.selected.opts and self.selected.opts.stop_context_insertion) or false,
    })
  end

  if self.selected.opts and self.selected.opts.user_prompt then
    vim.ui.input({ prompt = string.gsub(self.context.filetype, "^%l", string.upper) .. " Prompt" }, function(input)
      if not input then
        return
      end

      return chat(input)
    end)
  else
    return chat()
  end
end

---@return nil|CodeCompanion.Inline
function Strategies:inline()
  log:trace("Strategy: Inline")
  return require("codecompanion.strategies.inline")
    .new({
      context = self.context,
      opts = self.selected.opts,
      prompts = self.selected.prompts,
    })
    :start()
end

---@return nil|CodeCompanion.Chat
function Strategies:agent()
  local messages = process_prompts(self.selected.prompts, self.context)

  local adapter = config.adapters[config.strategies.agent.adapter]

  if type(adapter) == "string" then
    adapter = require("codecompanion.adapters").use(adapter)
    if not adapter then
      return nil
    end
  end

  log:trace("Strategy: Agent")
  return require("codecompanion.strategies.chat").new({
    adapter = adapter,
    type = self.selected.type,
    messages = messages,
    context = self.context,
  })
end

return Strategies
