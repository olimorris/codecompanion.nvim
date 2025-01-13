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

---Add a reference to the chat buffer
---@param prompt table
---@param chat CodeCompanion.Chat
local function add_ref(prompt, chat)
  if not prompt.references then
    return
  end

  local slash_commands = {
    file = require("codecompanion.strategies.chat.slash_commands.file").new({
      Chat = chat,
    }),
    symbols = require("codecompanion.strategies.chat.slash_commands.symbols").new({
      Chat = chat,
    }),
    url = require("codecompanion.strategies.chat.slash_commands.fetch").new({
      Chat = chat,
      config = config.strategies.chat.slash_commands["fetch"],
    }),
  }

  ---Get the file or symbols from a given path
  ---@param path string
  ---@param type string
  ---@return nil
  local function get_file(path, type)
    return slash_commands[type]:output({ path = path }, { silent = true })
  end

  ---Get the contents of the given URL
  ---@param url string
  ---@param type string
  ---@return nil
  local function get_url(url, type)
    return slash_commands[type]:output(url, { silent = true })
  end

  vim.iter(prompt.references):each(function(ref)
    if ref.type == "file" or ref.type == "symbols" then
      if type(ref.path) == "string" then
        return get_file(ref.path, ref.type)
      elseif type(ref.path) == "table" then
        for _, path in ipairs(ref.path) do
          get_file(path, ref.type)
        end
      end
    elseif ref.type == "url" then
      if type(ref.url) == "string" then
        get_url(ref.url, ref.type)
      elseif type(ref.url) == "table" then
        for _, url in ipairs(ref.url) do
          get_url(url, ref.type)
        end
      end
    end
  end)
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
    return log:warn("No messages to submit")
  end

  local function create_chat(input)
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

      vim.ui.input({
        prompt = string.gsub(self.context.filetype, "^%l", string.upper) .. " " .. config.display.action_palette.prompt,
      }, function(input)
        if not input then
          return
        end

        local chat = create_chat(input)
        return add_ref(self.selected, chat)
      end)
    else
      local chat = create_chat()
      return add_ref(self.selected, chat)
    end
  end

  local chat = create_chat()
  return add_ref(self.selected, chat)
end

---@return CodeCompanion.Chat|nil
function Strategies:workflow()
  local workflow = self.selected
  local stages = #workflow.prompts

  -- Expand the prompts
  local eval_prompts = vim
    .iter(workflow.prompts)
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
    auto_submit = (messages[#messages].opts and messages[#messages].opts.auto_submit) or false,
  })
  table.remove(eval_prompts, 1)

  -- Then when it completes we send the next batch and so on
  if stages > 1 then
    local order = 1
    vim.iter(eval_prompts):each(function(prompts)
      for i, prompt in ipairs(prompts) do
        chat:subscribe({
          id = math.random(10000000),
          order = order,
          type = "once",
          ---@param chat_obj CodeCompanion.Chat
          callback = function(chat_obj)
            vim.schedule(function()
              chat_obj:add_buf_message(prompt)
              if i == #prompts and prompt.opts and prompt.opts.auto_submit then
                chat_obj:submit()
              end
            end)
          end,
        })
      end
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
      return not (prompt.opts and prompt.opts.contains_code and not config.can_send_code())
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
