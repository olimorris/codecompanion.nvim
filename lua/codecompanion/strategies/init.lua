local adapters = require("codecompanion.adapters")
local config = require("codecompanion.config")

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
    messages = self.evaluate_prompts(prompts[mode], self.context)
  else
    -- No mode specified
    messages = self.evaluate_prompts(prompts, self.context)
  end

  if not messages or #messages == 0 then
    log:warn("No messages to submit")
    return
  end

  local function chat(input)
    if input then
      table.insert(messages, {
        role = config.constants.USER_ROLE,
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

      vim.ui.input({
        prompt = string.gsub(self.context.filetype, "^%l", string.upper) .. " " .. config.display.action_palette.prompt,
      }, function(input)
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

---@return CodeCompanion.Chat|nil
function Strategies:workflow()
  local workflow = self.selected
  local prompts = workflow.prompts
  local opts = workflow.opts
  local stages = #prompts

  -- Expand the prompts
  local eval_prompts = vim
    .iter(prompts)
    :map(function(prompt_group)
      return vim
        .iter(prompt_group)
        :map(function(prompt)
          local new_prompt = vim.deepcopy(prompt)
          if type(new_prompt.content) == "function" then
            new_prompt.content = new_prompt.content(self.context)
          end
          return new_prompt
        end)
        :totable()
    end)
    :totable()

  local messages = eval_prompts[1]

  -- We send the first batch of prompts to the chat buffer as messages
  local chat = require("codecompanion.strategies.chat").new({
    adapter = self.selected.adapter,
    context = self.context,
    messages = messages,
    auto_submit = (messages.opts and messages.opts.auto_submit) or false,
  })
  table.remove(eval_prompts, 1)

  -- Then when it completes we send the next batch and so on
  if stages > 1 then
    local order = 1
    vim.iter(eval_prompts):each(function(prompt)
      prompt = prompt[1]
      local event = {
        id = math.random(10000000),
        order = order,
        type = "once",
        callback = function(chat_obj)
          chat_obj:add_buf_message(prompt)
          if prompt.opts and prompt.opts.auto_submit then
            chat_obj:submit()
          end
        end,
      }
      chat:subscribe(event)
      order = order + 1
    end)
  end
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

---Evaluate a set of prompts based on conditionals and context
---@param prompts table
---@param context table
---@return table
function Strategies.evaluate_prompts(prompts, context)
  if type(prompts) ~= "table" or vim.tbl_isempty(prompts) then
    return {}
  end

  return vim
    .iter(prompts)
    :filter(function(prompt)
      return not (prompt.opts and prompt.opts.contains_code and not config.opts.send_code)
        and not (prompt.condition and not prompt.condition(context))
    end)
    :map(function(prompt)
      local content = type(prompt.content) == "function" and prompt.content(context) or prompt.content
      return {
        role = prompt.role or "",
        content = content,
        opts = prompt.opts or {},
      }
    end)
    :totable()
end

return Strategies
