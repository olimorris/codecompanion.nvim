local adapters = require("codecompanion.adapters")
local config = require("codecompanion").config

local log = require("codecompanion.utils.log")

---A user may specify an adapter for the prompt
---@param strategy CodeCompanion.Strategies
---@param opts table
---@return nil
local function add_adapter(strategy, opts)
  if opts.adapter and opts.adapter.name then
    strategy.selected.adapter = adapters.resolve(config.adapters[opts.adapter.name])
    if opts.adapter.model then
      strategy.selected.adapter.schema.model.default = opts.adapter.model
    end
  end
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

---Evaluate a set of prompts based on conditionals and context
---@param prompts table
---@return table
function Strategies:evaluate_prompts(prompts)
  local messages = {}

  for _, prompt in ipairs(prompts) do
    if prompt.opts and prompt.opts.contains_code and not config.opts.send_code then
      goto continue
    end
    if prompt.condition and not prompt.condition(self.context) then
      goto continue
    end

    local content
    if type(prompt.content) == "function" then
      content = prompt.content(self.context)
    else
      content = prompt.content
    end

    table.insert(messages, {
      role = prompt.role,
      content = content,
      opts = prompt.opts or {},
    })

    ::continue::
  end

  return messages
end

---@return CodeCompanion.Chat|nil
function Strategies:start(strategy)
  return self[strategy](self)
end

---@return CodeCompanion.Chat|nil
function Strategies:chat()
  local messages

  local opts = self.selected.opts
  local mode = self.context.mode:lower()
  local prompts = self.selected.prompts

  if type(prompts[mode]) == "function" then
    return prompts[mode]()
  elseif type(prompts[mode]) == "table" then
    messages = self:evaluate_prompts(prompts[mode])
  else
    -- No mode specified
    messages = self:evaluate_prompts(prompts)
  end

  if not messages or #messages == 0 then
    log:warn("No messages to submit")
    return
  end

  local function chat(input)
    if input then
      table.insert(messages, {
        role = "user",
        content = input,
      })
    end

    log:info("Strategy: Chat")
    return require("codecompanion.strategies.chat").new({
      adapter = self.selected.adapter,
      context = self.context,
      messages = messages,
      auto_submit = (opts and opts.auto_submit) or false,
      stop_context_insertion = (opts and self.selected.opts.stop_context_insertion) or false,
    })
  end

  if opts then
    -- Add an adapter
    add_adapter(self, opts)

    -- Prompt the user
    if opts.user_prompt then
      if type(opts.user_prompt) == "string" then
        return chat(opts.user_prompt)
      end

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

  return chat()
end

---@return CodeCompanion.Inline|nil
function Strategies:inline()
  log:info("Strategy: Inline")

  local opts = self.selected.opts

  if opts then
    add_adapter(self, opts)
  end

  return require("codecompanion.strategies.inline")
    .new({
      adapter = self.selected.adapter,
      context = self.context,
      opts = opts,
      prompts = self.selected.prompts,
    })
    :start()
end

return Strategies
