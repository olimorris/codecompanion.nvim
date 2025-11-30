local _extensions = require("codecompanion._extensions")
local config = require("codecompanion.config")
local context_utils = require("codecompanion.utils.context")
local log = require("codecompanion.utils.log")
local rules_helpers = require("codecompanion.strategies.chat.rules.helpers")
local utils = require("codecompanion.utils")

local api = vim.api

---@class CodeCompanion
local CodeCompanion = {
  ---@type table Access to extension exports via extensions.foo
  extensions = _extensions.manager,
}

---Register an extension with setup and exports
---@param name string The name of the extension
---@param extension CodeCompanion.Extension The extension implementation
---@return nil
CodeCompanion.register_extension = function(name, extension)
  local ok, ext_error = pcall(_extensions.register_extension, name, extension)
  if not ok then
    log:error("Error loading extension %s: %s", name, ext_error)
  end
end

---Run the inline assistant from the current Neovim buffer
---@param args table
---@return nil
CodeCompanion.inline = function(args)
  local context = context_utils.get(api.nvim_get_current_buf(), args)
  return require("codecompanion.strategies.inline").new({ buffer_context = context }):prompt(args.args)
end

---Accept the next word
---@return nil
CodeCompanion.inline_accept_word = function()
  if vim.fn.has("nvim-0.12") == 0 then
    return log:warn("Inline completion requires Neovim 0.12+")
  end
  return require("codecompanion.strategies.inline.completion").accept_word()
end

---Accept the next line
---@return nil
CodeCompanion.inline_accept_line = function()
  if vim.fn.has("nvim-0.12") == 0 then
    return log:warn("Inline completion requires Neovim 0.12+")
  end
  return require("codecompanion.strategies.inline.completion").accept_line()
end

---Initiate a prompt from the prompt library
---@param prompt table The prompt to resolve from the command
---@param args table The arguments that were passed to the command
---@return nil
CodeCompanion.prompt_library = function(prompt, args)
  local context = context_utils.get(api.nvim_get_current_buf(), args)

  -- A user may add a further prompt
  if prompt.opts and prompt.opts.user_prompt and args.user_prompt then
    prompt.opts.user_prompt = args.user_prompt
  end

  return require("codecompanion.strategies")
    .new({
      buffer_context = context,
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
      buffer_context = context,
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
---@param args? { auto_submit: boolean, params: table, subcommand: table,  callbacks: table, context: table, messages: CodeCompanion.Chat.Messages, user_prompt: table, window_opts: table }
---@return CodeCompanion.Chat|nil
CodeCompanion.chat = function(args)
  args = args or {}

  local adapter
  local messages = args.messages or {}
  local context = args.context or context_utils.get(api.nvim_get_current_buf(), args)

  -- Set the adapter and model if provided
  if args.params and args.params.adapter then
    local adapter_name = args.params.adapter
    adapter = config.adapters[adapter_name] or config.adapters.http[adapter_name] or config.adapters.acp[adapter_name]
    adapter = require("codecompanion.adapters").resolve(adapter)
    if args.params.model then
      adapter.schema.model.default = args.params.model
    end
  end

  if args.subcommand then
    if args.subcommand == "add" then
      return CodeCompanion.add(args)
    elseif args.subcommand == "toggle" then
      return CodeCompanion.toggle(args)
    elseif args.subcommand == "refreshcache" then
      return CodeCompanion.refresh_cache()
    end
  end

  -- Manage user prompts
  if args.user_prompt and #args.user_prompt > 0 then
    table.insert(messages, {
      role = config.constants.USER_ROLE,
      content = args.user_prompt,
    })
  end

  local has_messages = not vim.tbl_isempty(messages)
  local auto_submit = has_messages -- Don't auto submit if there are no messages
  if args.auto_submit ~= nil then
    auto_submit = args.auto_submit
  end

  -- Add rules to the chat buffer
  local rules_cb = rules_helpers.add_callbacks(args)
  if rules_cb then
    args.callbacks = rules_cb
  end

  return require("codecompanion.strategies.chat").new({
    adapter = adapter,
    auto_submit = auto_submit,
    buffer_context = context,
    callbacks = args.callbacks,
    messages = has_messages and messages or nil,
    window_opts = args and args.window_opts,
  })
end

---Create a cmd
---@return nil
CodeCompanion.cmd = function(args)
  local context = context_utils.get(api.nvim_get_current_buf(), args)

  return require("codecompanion.strategies.cmd")
    .new({
      buffer_context = context,
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
---@param opts? table
---@return nil
CodeCompanion.toggle = function(opts)
  local window_opts = opts and opts.window_opts

  local chat = CodeCompanion.last_chat()
  if not chat then
    return CodeCompanion.chat(window_opts and { window_opts = window_opts })
  end

  if chat.ui:is_visible_non_curtab() then
    chat.ui:hide()
  elseif chat.ui:is_visible() then
    return chat.ui:hide()
  end

  chat.buffer_context = context_utils.get(api.nvim_get_current_buf())
  CodeCompanion.close_last_chat()

  opts = { toggled = true }
  if window_opts then
    opts.window_opts = window_opts
  end
  chat.ui:open(opts)
end

---Make a previously hidden chat buffer, visible again
---@param bufnr number
---@return nil
CodeCompanion.restore = function(bufnr)
  if not bufnr or not api.nvim_buf_is_valid(bufnr) then
    return log:error("Chat buffer %d is not valid", bufnr)
  end

  local chat = require("codecompanion.strategies.chat").buf_get_chat(bufnr)
  if not chat then
    return log:error("Could not restore the chat buffer")
  end

  if chat.ui:is_visible() then
    if chat.ui.winnr and api.nvim_win_is_valid(chat.ui.winnr) then
      pcall(api.nvim_set_current_win, chat.ui.winnr)
    end
    return
  end
  chat.ui:open()
end

---Return a chat buffer
---@param bufnr? number
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

---Refresh any of the caches used by the plugin
---@return nil
CodeCompanion.refresh_cache = function()
  require("codecompanion.strategies.chat.tools.filter").refresh_cache()
  require("codecompanion.strategies.chat.slash_commands.filter").refresh_cache()
  utils.notify("Refreshed the cache for all chat buffers", vim.log.levels.INFO)
end

---Check if a feature is available in the plugin's current version
---@param feature? string|table
---@return boolean|table
CodeCompanion.has = function(feature)
  local features = {
    "chat",
    "inline-assistant",
    "cmd",
    "prompt-library",
    "function-calling",
    "extensions",
    "acp",
    "rules",
  }

  if type(feature) == "string" then
    return vim.tbl_contains(features, feature)
  end
  if type(feature) == "table" then
    for _, f in ipairs(feature) do
      if not vim.tbl_contains(features, f) then
        return false
      end
    end
    return true
  end
  return features
end

---Setup the plugin
---@param opts? table
---@return nil
CodeCompanion.setup = function(opts)
  opts = opts or {}

  -- Setup the plugin's config
  config.setup(opts)

  -- Handle ACP adapter config
  if opts and opts.adapters and opts.adapters.acp then
    if config.adapters.acp.opts.show_defaults then
      require("codecompanion.utils.adapters").extend(config.adapters.acp, opts.adapters.acp)
    else
      local copied = vim.deepcopy(opts.adapters.acp)
      config.adapters.acp = copied
    end
  end

  -- Handle HTTP adapter config
  if opts and opts.adapters and opts.adapters.http then
    if config.adapters.http.opts.show_defaults then
      require("codecompanion.utils.adapters").extend(config.adapters.http, opts.adapters.http)
    else
      local copied = vim.deepcopy(opts.adapters.http)
      config.adapters.http = copied
    end
  end

  local cmds = require("codecompanion.commands")
  for _, cmd in ipairs(cmds) do
    api.nvim_create_user_command(cmd.cmd, cmd.callback, cmd.opts)
  end

  -- Set up completion
  local completion = config.strategies.chat.opts.completion_provider
  pcall(function()
    return require("codecompanion.providers.completion." .. completion .. ".setup")
  end)

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

  -- Setup extensions
  for name, schema in pairs(config.extensions) do
    if schema.enabled ~= false then
      local ok, ext_error = pcall(_extensions.load_extension, name, schema)
      if not ok then
        log:error("Error loading extension %s: %s", name, ext_error)
      end
    end
  end

  local window_config = config.display.chat.window
  if window_config.sticky and (window_config.layout ~= "buffer") then
    api.nvim_create_autocmd("TabEnter", {
      group = api.nvim_create_augroup("codecompanion.sticky_buffer", { clear = true }),
      callback = function(args)
        local chat = CodeCompanion.last_chat()
        if chat and chat.ui:is_visible_non_curtab() then
          chat.buffer_context = context_utils.get(args.buf)
          vim.schedule(function()
            CodeCompanion.close_last_chat()
            chat.ui:open({ toggled = true })
          end)
        end
      end,
    })
  end
end

return CodeCompanion
