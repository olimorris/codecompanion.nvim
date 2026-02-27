local adapters = require("codecompanion.adapters")
local config = require("codecompanion.config")

local log = require("codecompanion.utils.log")
local rules_helpers = require("codecompanion.interactions.chat.rules.helpers")

---A user may specify an adapter for the prompt
---@param interaction CodeCompanion.Interactions
---@param opts table
---@return nil
local function add_adapter(interaction, opts)
  if opts.adapter and opts.adapter.name then
    interaction.selected.adapter = adapters.resolve(opts.adapter.name, { model = opts.adapter.model })
  end
end

---Extract tools from the selected prompt
---@param selected table
---@return table<string>|nil
local function get_tools(selected)
  return selected.tools
end

---Extract MCP servers from the selected prompt
---@param selected table
---@return table<string>|nil
local function get_mcp_servers(selected)
  return selected.mcp_servers
end

---Build callbacks from opts and rules
---@param selected table The selected prompt
---@return table
local function get_callbacks(selected)
  local opts = selected.opts or {}
  local callbacks = opts.callbacks or {}

  --TODO: Remove opts.rules fallback in v20.0.0
  local rules = selected.rules or opts.rules
  if rules and rules ~= "none" then
    local rules_cb = rules_helpers.add_callbacks(callbacks, rules)
    if rules_cb then
      callbacks = rules_cb
    end
  end
  return callbacks
end

---@class CodeCompanion.Interactions
---@field buffer_context CodeCompanion.BufferContext
---@field selected table
local Interactions = {}

---@class CodeCompanion.InteractionArgs
---@field buffer_context CodeCompanion.BufferContext
---@field selected table

---@param args CodeCompanion.InteractionArgs
function Interactions.new(args)
  log:trace("Buffer Context: %s", args.buffer_context)

  return setmetatable({
    called = {},
    buffer_context = args.buffer_context,
    selected = args.selected,
  }, { __index = Interactions })
end

---@param interaction string
function Interactions:start(interaction)
  return self[interaction](self)
end

---Add context to the chat buffer
---@param prompt table
---@param chat CodeCompanion.Chat
function Interactions.add_context(prompt, chat)
  local context = prompt.context
  if not context or vim.tbl_isempty(context) then
    return
  end

  local slash_commands = require("codecompanion.interactions.chat.slash_commands")

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

---Start a chat interaction
---@return CodeCompanion.Chat|nil
function Interactions:chat()
  local messages

  local opts = self.selected.opts

  -- Handle workflows separately
  if opts and opts.is_workflow then
    return self:workflow()
  end

  local mode = self.buffer_context.mode:lower()
  local prompts = self.selected.prompts

  if type(prompts[mode]) == "function" then
    return prompts[mode](self.buffer_context)
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

    if type(opts.pre_hook) == "function" then
      opts.pre_hook()
    end

    log:info("[Interaction] Chat Initiated")
    return require("codecompanion.interactions.chat").new({
      adapter = self.selected.adapter,
      auto_submit = (opts and opts.auto_submit) or false,
      buffer_context = self.buffer_context,
      callbacks = get_callbacks(self.selected),
      from_prompt_library = self.selected.description and true or false,
      ignore_system_prompt = (opts and opts.ignore_system_prompt) or false,
      intro_message = (opts and opts.intro_message) or nil,
      mcp_servers = get_mcp_servers(self.selected),
      messages = messages,
      stop_context_insertion = (opts and self.selected.opts.stop_context_insertion) or false,
      tools = get_tools(self.selected),
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

---Start a chat interaction with a workflow
---@return CodeCompanion.Chat
function Interactions:workflow()
  local workflow = self.selected
  local stages = #workflow.prompts

  log:info("[Interaction] Workflow Initiated")

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
            p.opts = { visible = false, _meta = { tag = "from_custom_prompt" } }
          end
          return p
        end)
        :totable()
    end)
    :totable()

  local messages = prompts[1]

  -- Set the workflow adapter if one is specified
  add_adapter(self, workflow.opts or {})

  -- We send the first batch of prompts to the chat buffer as messages
  local chat = require("codecompanion.interactions.chat").new({
    adapter = self.selected.adapter,
    auto_submit = (messages[#messages].opts and messages[#messages].opts.auto_submit) or false,
    buffer_context = self.buffer_context,
    callbacks = get_callbacks(self.selected),
    mcp_servers = get_mcp_servers(self.selected),
    messages = messages,
    tools = get_tools(self.selected),
  })

  if workflow.context then
    self.add_context(workflow, chat)
  end

  table.remove(prompts, 1)

  -- Then when it completes we send the next batch and so on
  if stages > 1 then
    local order = 1
    vim.iter(prompts):each(function(prompt)
      for _, val in ipairs(prompt) do
        local event_type = (type(val.repeat_until) == "function") and "repeat" or "once"
        local event_data = vim.tbl_deep_extend("keep", {}, val, { type = event_type })
        local event = {
          callback = function()
            if type(val.content) == "function" then
              val.content = val.content(self.buffer_context)
            end
            chat:add_buf_message(val)
            if val.opts and val.opts.adapter and val.opts.adapter.name then
              chat:change_adapter(val.opts.adapter.name, val.opts.adapter.model)
            end
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

---Start an inline interaction
---@return CodeCompanion.Inline|nil
function Interactions:inline()
  log:info("[Interaction] Inline Initiated")

  local opts = self.selected.opts

  if opts then
    add_adapter(self, opts)
  end

  -- Make testing easier by assigning this to a field
  self.called = require("codecompanion.interactions.inline").new({
    adapter = self.selected.adapter,
    buffer_context = self.buffer_context,
    opts = opts,
    prompts = self.selected.prompts,
  })

  return self.called:prompt()
end

---Evaluate a set of prompts based on conditionals and context
---@param prompts table
---@param buffer_context CodeCompanion.BufferContext
---@return table
function Interactions.evaluate_prompts(prompts, buffer_context)
  if type(prompts) ~= "table" or vim.tbl_isempty(prompts) then
    return {}
  end

  return vim
    .iter(prompts)
    :filter(function(prompt)
      return not (prompt.opts and prompt.opts.contains_code and not config.can_send_code())
        and not (prompt.condition and not prompt.condition(buffer_context))
    end)
    :map(function(prompt)
      local content = type(prompt.content) == "function" and prompt.content(buffer_context) or prompt.content
      if prompt.role == config.constants.SYSTEM_ROLE and not prompt.opts then
        prompt.opts = { visible = false, _meta = { tag = "from_custom_prompt" } }
      end
      return {
        role = prompt.role or "",
        content = content,
        opts = prompt.opts or {},
      }
    end)
    :totable()
end

return Interactions
