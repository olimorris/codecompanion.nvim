local adapters = require("codecompanion.adapters")
local config = require("codecompanion.config")

local log = require("codecompanion.utils.log")

---A user may specify an adapter for the prompt
---@param strategy CodeCompanion.Strategies
---@param opts table
---@return nil
local function add_adapter(strategy, opts)
  if opts.adapter and opts.adapter.name then
    strategy.selected.adapter = adapters.resolve(opts.adapter.name, { model = opts.adapter.model })
  end
end

---@class CodeCompanion.Strategies
---@field buffer_context table
---@field selected table
local Strategies = {}

---@class CodeCompanion.StrategyArgs
---@field buffer_context table
---@field selected table

---@param args CodeCompanion.StrategyArgs
function Strategies.new(args)
  log:trace("Buffer Context: %s", args.buffer_context)

  return setmetatable({
    called = {},
    buffer_context = args.buffer_context,
    selected = args.selected,
  }, { __index = Strategies })
end

---@param strategy string
function Strategies:start(strategy)
  return self[strategy](self)
end

---Add context to the chat buffer
---@param prompt table
---@param chat CodeCompanion.Chat
function Strategies.add_context(prompt, chat)
  --TODO: remove prompt.references in v18.0.0
  local context = prompt.references or prompt.context

  if not context or vim.tbl_isempty(context) then
    return
  end

  ---TODO: Remove this in v18.0.0
  if prompt.references then
    vim.deprecate(
      "`references` in the prompt library are now deprecated",
      "Please use `context` instead",
      "v18.0.0",
      "CodeCompanion",
      false
    )
  end

  local slash_commands = require("codecompanion.strategies.chat.slash_commands")

  vim.iter(context):each(function(item)
    if item.type == "file" or item.type == "symbols" then
      if type(item.path) == "string" then
        return slash_commands.context(chat, item.type, { path = item.path })
      elseif type(item.path) == "table" then
        for _, path in ipairs(item.path) do
          slash_commands.context(chat, item.type, { path = path })
        end
      end
    elseif item.type == "url" then
      if type(item.url) == "string" then
        return slash_commands.context(chat, item.type, { url = item.url })
      elseif type(item.url) == "table" then
        for _, url in ipairs(item.url) do
          slash_commands.context(chat, item.type, { url = url })
        end
      end
    end
  end)
end

---@return CodeCompanion.Chat|nil
function Strategies:chat()
  local messages

  local opts = self.selected.opts
  local mode = self.buffer_context.mode:lower()
  local prompts = self.selected.prompts

  if type(prompts[mode]) == "function" then
    return prompts[mode]()
  elseif type(prompts[mode]) == "table" then
    messages = self.evaluate_prompts(prompts[mode], self.buffer_context)
  else
    -- No mode specified
    messages = self.evaluate_prompts(prompts, self.buffer_context)
  end

  if not messages or #messages == 0 then
    return log:warn("No messages to submit")
  end

  local function create_chat(input)
    if input then
      table.insert(messages, {
        role = config.constants.USER_ROLE,
        content = input,
      })
    end

    log:info("[Strategy] Chat Initiated")
    return require("codecompanion.strategies.chat").new({
      adapter = self.selected.adapter,
      buffer_context = self.buffer_context,
      messages = messages,
      from_prompt_library = self.selected.description and true or false,
      auto_submit = (opts and opts.auto_submit) or false,
      stop_context_insertion = (opts and self.selected.opts.stop_context_insertion) or false,
      ignore_system_prompt = (opts and opts.ignore_system_prompt) or false,
    })
  end

  if opts then
    -- Add an adapter
    add_adapter(self, opts)

    -- Prompt the user
    if opts.user_prompt then
      if type(opts.user_prompt) == "string" then
        return create_chat(opts.user_prompt)
      end

      return vim.ui.input({
        prompt = string.gsub(self.buffer_context.filetype, "^%l", string.upper)
          .. " "
          .. config.display.action_palette.prompt,
      }, function(input)
        if not input then
          return
        end

        local chat = create_chat(input)
        return self.add_context(self.selected, chat)
      end)
    else
      local chat = create_chat()
      return self.add_context(self.selected, chat)
    end
  end

  local chat = create_chat()
  return self.add_context(self.selected, chat)
end

---@return CodeCompanion.Chat
function Strategies:workflow()
  local workflow = self.selected
  local stages = #workflow.prompts

  log:info("[Strategy] Workflow Initiated")

  -- Expand the prompts
  local prompts = vim
    .iter(workflow.prompts)
    :map(function(prompt_group)
      return vim
        .iter(prompt_group)
        :map(function(prompt)
          local p = vim.deepcopy(prompt)
          if type(p.content) == "function" then
            p.content = p.content(self.buffer_context)
          end
          if p.role == config.constants.SYSTEM_ROLE and not p.opts then
            p.opts = { visible = false, tags = { "from_custom_prompt" } }
          end
          return p
        end)
        :totable()
    end)
    :totable()

  local messages = prompts[1]

  -- We send the first batch of prompts to the chat buffer as messages
  local chat = require("codecompanion.strategies.chat").new({
    adapter = self.selected.adapter,
    auto_submit = (messages[#messages].opts and messages[#messages].opts.auto_submit) or false,
    buffer_context = self.buffer_context,
    messages = messages,
  })

  ---TODO: Remove workflow.references in v18.0.0
  if workflow.references or workflow.context then
    self.add_context(workflow, chat)
  end

  table.remove(prompts, 1)

  -- Then when it completes we send the next batch and so on
  if stages > 1 then
    local order = 1
    vim.iter(prompts):each(function(prompt)
      for _, val in ipairs(prompt) do
        local event_data = vim.tbl_deep_extend("keep", {}, val, { type = "once" })

        local event = {
          callback = function()
            if type(val.content) == "function" then
              val.content = val.content(self.buffer_context)
            end
            chat:add_buf_message(val)
          end,
          data = event_data,
          order = order,
        }

        if event_data.repeat_until then
          ---@param c CodeCompanion.Chat
          event.reuse = function(c)
            assert(type(val.repeat_until) == "function", "repeat_until must be a function")
            return val.repeat_until(c) == false
          end
        end

        chat.subscribers:subscribe(event)
      end
      order = order + 1
    end)
  end

  return chat
end

---@return CodeCompanion.Inline|nil
function Strategies:inline()
  log:info("[Strategy] Inline Initiated")

  local opts = self.selected.opts

  if opts then
    add_adapter(self, opts)
  end

  -- Allow us to test the inline strategy
  self.called = require("codecompanion.strategies.inline").new({
    adapter = self.selected.adapter,
    buffer_context = self.buffer_context,
    opts = opts,
    prompts = self.selected.prompts,
  })

  return self.called:prompt()
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
      return not (prompt.opts and prompt.opts.contains_code and not config.can_send_code())
        and not (prompt.condition and not prompt.condition(context))
    end)
    :map(function(prompt)
      local content = type(prompt.content) == "function" and prompt.content(context) or prompt.content
      if prompt.role == config.constants.SYSTEM_ROLE and not prompt.opts then
        prompt.opts = { visible = false, tags = { "from_custom_prompt" } }
      end
      return {
        role = prompt.role or "",
        content = content,
        opts = prompt.opts or {},
      }
    end)
    :totable()
end

return Strategies
