local config = require("codecompanion.config")
local context_utils = require("codecompanion.utils.context")
local log = require("codecompanion.utils.log")

local api = vim.api

---@class CodeCompanion
local CodeCompanion = {}

---Run the inline assistant from the current Neovim buffer
---@param args table
---@return nil
CodeCompanion.inline = function(args)
  local context = context_utils.get(api.nvim_get_current_buf(), args)
  return require("codecompanion.strategies.inline").new({ context = context }):prompt(args.args)
end

---Initiate a prompt from the prompt library
---@param prompt table The prompt to resolve from the command
---@param args table The arguments that were passed to the command
---@return nil
CodeCompanion.prompt_library = function(prompt, args)
  log:trace("Running inline prompt")
  local context = context_utils.get(api.nvim_get_current_buf(), args)

  -- A user may add a further prompt
  if prompt.opts and prompt.opts.user_prompt and args.user_prompt then
    log:trace("Adding custom user prompt")
    prompt.opts.user_prompt = args.user_prompt
  end

  return require("codecompanion.strategies")
    .new({
      context = context,
      selected = prompt,
    })
    :start(prompt.strategy)
end

---Run a prompt from the prompt library
---@param name string
---@param args table?
---@return nil
CodeCompanion.prompt = function(name, args)
  local context = context_utils.get(api.nvim_get_current_buf(), args)
  local prompt = vim
    .iter(config.prompt_library)
    :filter(function(_, v)
      return v.opts.short_name and (v.opts.short_name:lower() == name:lower()) or false
    end)
    :map(function(_, v)
      return v
    end)
    :totable()[1]

  if not prompt then
    return log:warn("Could not find '%s' in the prompt library", name)
  end

  return require("codecompanion.strategies")
    .new({
      context = context,
      selected = prompt,
    })
    :start(prompt.strategy)
end

--Add visually selected code to the current chat buffer
---@param args table
---@return nil
CodeCompanion.add = function(args)
  if not config.can_send_code() then
    return log:warn("Sending of code has been disabled")
  end

  local context = context_utils.get(api.nvim_get_current_buf(), args)
  local content = table.concat(context.lines, "\n")

  local chat = CodeCompanion.last_chat()

  if not chat then
    chat = CodeCompanion.chat()

    if not chat then
      return log:warn("Could not create chat buffer")
    end
  end

  chat:add_buf_message({
    role = config.constants.USER_ROLE,
    content = "Here is some code from "
      .. context.filename
      .. ":\n\n```"
      .. context.filetype
      .. "\n"
      .. content
      .. "\n```\n",
  })
  chat.ui:open()
end

---Open a chat buffer and converse with an LLM
---@param args? table
---@return nil
CodeCompanion.chat = function(args)
  local adapter
  local messages = {}
  local context = context_utils.get(api.nvim_get_current_buf(), args)

  if args and args.fargs and #args.fargs > 0 then
    local prompt = args.fargs[1]:lower()

    -- Check if the adapter is available
    adapter = config.adapters[prompt]

    if not adapter then
      if prompt == "add" then
        return CodeCompanion.add(args)
      elseif prompt == "toggle" then
        return CodeCompanion.toggle()
      else
        table.insert(messages, {
          role = config.constants.USER_ROLE,
          content = args.args,
        })
      end
    end
  end

  local has_messages = not vim.tbl_isempty(messages)

  return require("codecompanion.strategies.chat").new({
    context = context,
    adapter = adapter,
    messages = has_messages and messages or nil,
    auto_submit = has_messages,
  })
end

---Create a cmd
---@return nil
CodeCompanion.cmd = function(args)
  local context = context_utils.get(api.nvim_get_current_buf(), args)

  return require("codecompanion.strategies.cmd")
    .new({
      context = context,
      prompts = {
        {
          role = config.constants.SYSTEM_ROLE,
          content = string.format(
            [[Some additional context which **may** be useful:

- The user is currently working in a %s file
- It has %d lines
- The user is currently on line %d
- The file's full path is %s]],
            context.filetype,
            context.line_count,
            context.cursor_pos[1],
            context.filename
          ),
          opts = {
            visible = false,
          },
        },
        {
          role = config.constants.USER_ROLE,
          content = args.args,
        },
      },
    })
    :start(args)
end

---Toggle the chat buffer
---@return nil
CodeCompanion.toggle = function()
  local chat = CodeCompanion.last_chat()

  if not chat then
    return CodeCompanion.chat()
  end

  if chat.ui:is_visible() then
    return chat.ui:hide()
  end

  chat.context = context_utils.get(api.nvim_get_current_buf())
  CodeCompanion.close_last_chat()
  chat.ui:open()
end

---Return a chat buffer
---@param bufnr? integer
---@return CodeCompanion.Chat|table
CodeCompanion.buf_get_chat = function(bufnr)
  return require("codecompanion.strategies.chat").buf_get_chat(bufnr)
end

---Get the last chat buffer
---@return CodeCompanion.Chat|nil
CodeCompanion.last_chat = function()
  return require("codecompanion.strategies.chat").last_chat()
end

---Close the last chat buffer
---@return nil
CodeCompanion.close_last_chat = function()
  return require("codecompanion.strategies.chat").close_last_chat()
end

---Show the action palette
---@param args table
---@return nil
CodeCompanion.actions = function(args)
  local context = context_utils.get(api.nvim_get_current_buf(), args)
  return require("codecompanion.actions").launch(context, args)
end

---Return the JSON schema for the workspace file
---@return string|nil
CodeCompanion.workspace_schema = function()
  -- Credit: https://github.com/romgrk/fzy-lua-native/blob/master/lua/init.lua
  local dirname = string.sub(debug.getinfo(1).source, 2, string.len("/init.lua") * -1)

  local ok, file = pcall(function()
    return require("plenary.path"):new(dirname .. "workspace-schema.json"):read()
  end)

  if ok then
    return file
  end
end

---Setup the plugin
---@param opts? table
---@return nil
CodeCompanion.setup = function(opts)
  -- Setup the plugin's config
  config.setup(opts)
  if opts and opts.adapters then
    if config.adapters.opts.show_defaults then
      config.adapters = require("codecompanion.utils.adapters").extend(config.adapters, opts.adapters)
    else
      config.adapters = vim.deepcopy(opts.adapters)
    end
  end

  local cmds = require("codecompanion.commands")
  for _, cmd in ipairs(cmds) do
    api.nvim_create_user_command(cmd.cmd, cmd.callback, cmd.opts)
  end

  -- Set the log root
  log.set_root(log.new({
    handlers = {
      {
        type = "echo",
        level = vim.log.levels.ERROR,
      },
      {
        type = "notify",
        level = vim.log.levels.WARN,
      },
      {
        type = "file",
        filename = "codecompanion.log",
        level = vim.log.levels[config.opts.log_level],
      },
    },
  }))
end

return CodeCompanion
