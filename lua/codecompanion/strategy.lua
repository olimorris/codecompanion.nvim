local config = require("codecompanion").config
local log = require("codecompanion.utils.log")

---@param prompts table
---@param context table
local function modal_prompts(prompts, context)
  local messages = {}
  for _, prompt in ipairs(prompts) do
    --TODO: These nested conditionals suck. Refactor soon
    if not prompt.contains_code or (prompt.contains_code and config.send_code) then
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
---@field context table
---@field selected table
local Strategy = {}

---@class CodeCompanion.StrategyArgs
---@field context table
---@field selected table

---@param args CodeCompanion.StrategyArgs
---@return CodeCompanion.Strategy
function Strategy.new(args)
  log:trace("Context: %s", args.context)
  return setmetatable({
    context = args.context,
    selected = args.selected,
  }, { __index = Strategy })
end

function Strategy:start(strategy)
  return self[strategy](self)
end

---@return nil|CodeCompanion.Chat
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

  local function chat(input)
    if input then
      table.insert(messages, {
        role = "user",
        content = input,
      })
    end

    return require("codecompanion.strategies.chat").new({
      type = self.selected.type,
      messages = messages,
      show_buffer = true,
      auto_submit = (self.selected.opts and self.selected.opts.auto_submit) or false,
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

function Strategy:inline()
  return require("codecompanion.strategies.inline")
    .new({
      context = self.context,
      opts = self.selected.opts,
      pre_hook = self.selected.pre_hook,
      prompts = self.selected.prompts,
    })
    :start()
end

---@return nil|CodeCompanion.Chat
function Strategy:tool()
  local messages = modal_prompts(self.selected.prompts, self.context)

  local adapter = config.adapters[config.strategies.tool]

  if type(adapter) == "string" then
    adapter = require("codecompanion.adapters").use(adapter)
    if not adapter then
      return nil
    end
  end

  return require("codecompanion.strategies.chat").new({
    adapter = adapter,
    type = self.selected.type,
    messages = messages,
    show_buffer = true,
  })
end

return Strategy
