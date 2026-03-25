local _extensions = require("codecompanion._extensions")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local api = vim.api

local _last_toggle = "chat"
local _version

-- Lazy load context_utils
local context_utils
local function get_context(bufnr, args)
  if not context_utils then
    context_utils = require("codecompanion.utils.context")
  end
  return context_utils.get(bufnr, args)
end

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
  local context = get_context(api.nvim_get_current_buf(), args)
  local inline = require("codecompanion.interactions.inline").new({ buffer_context = context })
  if inline then
    inline:prompt(args.args)
  end
end

---Accept the next word of code completion
---@return nil
CodeCompanion.inline_accept_word = function()
  if vim.fn.has("nvim-0.12") == 0 then
    return log:warn("Inline completion requires Neovim 0.12+")
  end
  return require("codecompanion.interactions.inline.completion").accept_word()
end

---Accept the next line of code completion
---@return nil
CodeCompanion.inline_accept_line = function()
  if vim.fn.has("nvim-0.12") == 0 then
    return log:warn("Inline completion requires Neovim 0.12+")
  end
  return require("codecompanion.interactions.inline.completion").accept_line()
end

---Run a prompt from the prompt library
---@param alias string
---@param args table?
---@return nil
CodeCompanion.prompt = function(alias, args)
  local actions = require("codecompanion.actions")

  local context = get_context(api.nvim_get_current_buf(), args)
  local prompt = actions.resolve_from_alias(alias, context)

  if not prompt then
    return log:warn("Could not find `%s` in the prompt library", alias)
  end

  return actions.resolve(prompt, context)
end

---Add visually selected code to the current chat buffer
---@param args table
---@return nil
CodeCompanion.add = function(args)
  if not config.can_send_code() then
    return log:warn("Sending of code has been disabled")
  end

  local context = get_context(api.nvim_get_current_buf(), args)
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
      .. context.path
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
---@return CodeCompanion.Chat|nil
CodeCompanion.chat = function(args)
  args = args or {}

  local acp_command
  local adapter
  local messages = args.messages or {}
  local context = args.context or get_context(api.nvim_get_current_buf(), args)

  -- Set the adapter and model if provided
  if args.params and args.params.adapter then
    local adapter_name = args.params.adapter
    adapter = config.adapters.http[adapter_name] or config.adapters.acp[adapter_name]
    adapter = require("codecompanion.adapters").resolve(adapter)
    if args.params.model then
      adapter.schema.model.default = args.params.model
    end
    if adapter.type == "acp" and args.params.command then
      acp_command = args.params.command
    end
  end

  if args.subcommand then
    if args.subcommand == "add" then
      return CodeCompanion.add(args)
    elseif args.subcommand == "toggle" then
      return CodeCompanion.toggle_chat(args)
    elseif args.subcommand == "refreshcache" then
      return CodeCompanion.chat_refresh_cache()
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
  local rules_cb = require("codecompanion.interactions.chat.rules.helpers").add_callbacks(args)
  if rules_cb then
    args.callbacks = rules_cb
  end

  return require("codecompanion.interactions.chat").new({
    acp_command = acp_command,
    adapter = adapter,
    auto_submit = auto_submit,
    buffer_context = context,
    callbacks = args.callbacks,
    hidden = args.hidden,
    messages = has_messages and messages or nil,
    window_opts = args and args.window_opts,
  })
end

---Refresh any of the caches used by the plugin
---@return nil
CodeCompanion.chat_refresh_cache = function()
  require("codecompanion.interactions.chat.tools.filter").refresh_cache()
  require("codecompanion.interactions.chat.slash_commands.filter").refresh_cache()
  require("codecompanion.utils").notify("Refreshed the cache for all chat buffers", vim.log.levels.INFO)
end

---Create a cmd
---@return nil
CodeCompanion.cmd = function(args)
  local context = get_context(api.nvim_get_current_buf(), args)

  local command = require("codecompanion.interactions.cmd").new({
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
          context.path
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

  if command then
    command:start(args)
  end
end

---Toggle the most recently used interaction (chat or CLI)
---If either is visible, hide it. If neither is visible, show the last used one.
---@param args? table
---@return nil
CodeCompanion.toggle = function(args)
  local cli = require("codecompanion.interactions.cli")
  local chat = require("codecompanion.interactions.chat")

  -- If the CLI is visible, hide it
  if cli.is_visible() then
    _last_toggle = "cli"
    return cli.get_visible().ui:hide()
  end

  -- If the chat is visible, hide it
  if chat.is_visible() then
    _last_toggle = "chat"
    return chat.last_chat().ui:hide()
  end

  -- Neither is visible — show the last used one
  if _last_toggle == "cli" then
    return CodeCompanion.toggle_cli(args)
  end

  return CodeCompanion.toggle_chat(args)
end

---Toggle the chat buffer specifically
---@param args? table
---@return nil
CodeCompanion.toggle_chat = function(args)
  _last_toggle = "chat"
  return require("codecompanion.interactions.chat").toggle({
    params = args and args.params,
    window_opts = args and args.window_opts,
    context = get_context(api.nvim_get_current_buf()),
  })
end

---Make a previously hidden chat buffer, visible again
---@param bufnr number
---@return nil
CodeCompanion.restore = function(bufnr)
  if not bufnr or not api.nvim_buf_is_valid(bufnr) then
    return log:error("Chat buffer %d is not valid", bufnr)
  end

  local chat = require("codecompanion.interactions.chat").buf_get_chat(bufnr)
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
  return require("codecompanion.interactions.chat").buf_get_chat(bufnr)
end

---Get the last chat buffer
---@return CodeCompanion.Chat|nil
CodeCompanion.last_chat = function()
  return require("codecompanion.interactions.chat").last_chat()
end

---Close the last chat buffer
---@return nil
CodeCompanion.close_last_chat = function()
  return require("codecompanion.interactions.chat").close_last_chat()
end

---Open, send to, or interact with a CLI agent
---@param prompt_or_opts? string|table A prompt string, or an opts table when no prompt is needed
---@param opts? { agent?: string, focus?: boolean, submit?: boolean, prompt?: boolean, width?: number, height?: number, args?: table }
---@return nil
CodeCompanion.cli = function(prompt_or_opts, opts)
  local prompt

  if type(prompt_or_opts) == "table" then
    opts = prompt_or_opts
  elseif type(prompt_or_opts) == "string" then
    prompt = prompt_or_opts
  end
  opts = opts or {}

  -- Prompt input mode: toggle the input buffer
  if opts.prompt then
    return require("codecompanion.interactions.cli.input").toggle({
      agent = opts.agent,
      args = opts.args,
      initial_content = prompt,
    })
  end

  local context
  if prompt then
    context = get_context(api.nvim_get_current_buf(), opts.args)
  end

  local cli = require("codecompanion.interactions.cli")
  local instance
  if prompt then
    if opts.agent then
      instance = cli.find_by_agent(opts.agent) or cli.create({ agent = opts.agent })
    else
      instance = cli.last_cli() or cli.create()
    end
  else
    instance = cli.create({ agent = opts.agent })
  end

  if not instance then
    return log:error("Could not create CLI instance")
  end

  local should_focus = opts.focus ~= false

  if not instance.ui:is_visible() and should_focus then
    local ui_opts = {}
    if opts.width then
      ui_opts.width = opts.width
    end
    if opts.height then
      ui_opts.height = opts.height
    end
    instance.ui:open(ui_opts)
  end

  if prompt then
    local resolved = cli.resolve_editor_context(prompt, context)

    -- When not submitting, append a newline so successive cli() calls
    -- don't stack text on the same terminal line. Skip when submitting
    -- because the \r handles the line ending and a trailing \n would be
    -- interpreted as an extra Enter by the TUI agent.
    if not opts.submit and not resolved:match("\n$") then
      resolved = resolved .. "\n"
    end

    instance:send(resolved, { submit = opts.submit })
  end

  if should_focus and prompt then
    instance:focus()
  end

  _last_toggle = "cli"
end

---Toggle the CLI terminal buffer
---@param args? { agent?: string }
---@return nil
CodeCompanion.toggle_cli = function(args)
  _last_toggle = "cli"
  return require("codecompanion.interactions.cli").toggle(args)
end

---Show the action palette
---@param args table
---@return nil
CodeCompanion.actions = function(args)
  local context = get_context(api.nvim_get_current_buf(), args)
  return require("codecompanion.actions").launch(context, args)
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
    "cli",
    "inline",
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

---Output the plugin version
---@return string|nil
CodeCompanion.version = function()
  if _version then
    return _version
  end

  local ok, version = pcall(function()
    return require("codecompanion.utils.files")
      .read(
        vim.fs.joinpath(
          string.sub(debug.getinfo(1).source, 2, string.len("/lua/codecompanion/init.lua") * -1),
          "version.txt"
        )
      )
      :gsub("%s+", "")
  end)

  if ok then
    _version = version
    return _version
  end

  return nil
end

---Handle adapter configuration merging
---@param adapter_type string
---@param opts table
---@return nil
local function adapter_config(adapter_type, opts)
  if opts and opts.adapters and opts.adapters[adapter_type] then
    if config.adapters[adapter_type].opts.show_presets then
      local adapters_util = require("codecompanion.utils.adapters")
      adapters_util.extend(config.adapters[adapter_type], opts.adapters[adapter_type])
    else
      config.adapters[adapter_type] =
        vim.tbl_deep_extend("keep", opts.adapters[adapter_type], { opts = config.adapters[adapter_type].opts })
    end
  end
end

---Setup the plugin
---@param opts? table
---@return nil
CodeCompanion.setup = function(opts)
  opts = opts or {}

  -- Setup the plugin's config
  config.setup(opts)

  adapter_config("acp", opts)
  adapter_config("http", opts)

  local cmds = require("codecompanion.commands")
  for _, cmd in ipairs(cmds) do
    api.nvim_create_user_command(cmd.cmd, cmd.callback, cmd.opts)
  end

  -- Load the main completion module first to register its autocmds
  require("codecompanion.providers.completion")
  local completion = config.interactions.chat.opts.completion_provider
  local ok, completion_module = pcall(require, "codecompanion.providers.completion." .. completion .. ".setup")
  if not ok then
    log:warn("Failed to load completion provider `%s`: %s", completion, completion_module)
  end

  -- Set the log root
  log.set_root(log.new({
    handlers = {
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
  if window_config.sticky and window_config.layout ~= "buffer" and window_config.layout ~= "tab" then
    api.nvim_create_autocmd("TabEnter", {
      group = api.nvim_create_augroup("codecompanion.sticky_buffer", { clear = true }),
      callback = function(args)
        local chat = CodeCompanion.last_chat()
        if chat and chat.ui:is_visible_non_curtab() then
          chat.buffer_context = get_context(args.buf)
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
