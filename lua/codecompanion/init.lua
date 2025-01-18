local config = require("codecompanion.config")
local context_utils = require("codecompanion.utils.context")
local log = require("codecompanion.utils.log")

local api = vim.api

---@class CodeCompanion
---@field last_chat fun(): CodeCompanion.Chat|nil
local M = {}

---Prompt the LLM from within the current buffer
---@param args table
---@return nil|CodeCompanion.Inline
M.inline = function(args)
  local context = context_utils.get(api.nvim_get_current_buf(), args)

  return require("codecompanion.strategies.inline")
    .new({
      context = context,
      prompts = {
        {
          role = config.constants.SYSTEM_ROLE,
          content = function()
            return "I want you to act as a senior "
              .. context.filetype
              .. " developer. I will ask you specific questions and I want you to return raw code only. No markdown codeblocks with backticks and no explanations. If you can't respond with code, respond with nothing."
          end,
          opts = {
            visible = false,
            tag = "system_tag",
          },
        },
      },
    })
    :start(args)
end

---Run a prompt from the prompt library
---@param name string
---@param args table?
---@return nil
M.prompt = function(name, args)
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

---Run the prompt that the user initiated from the command line
---@param prompt table The prompt to resolve from the command
---@param args table The arguments that were passed to the command
---@return nil
M.run_inline_prompt = function(prompt, args)
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

--Add visually selected code to the current chat buffer
---@param args table
---@return nil
M.add = function(args)
  if not config.can_send_code() then
    return log:warn("Sending of code has been disabled")
  end

  local context = context_utils.get(api.nvim_get_current_buf(), args)
  local content = table.concat(context.lines, "\n")

  local chat = M.last_chat()

  if not chat then
    chat = M.chat()

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
M.chat = function(args)
  local adapter
  local messages = {}
  local context = context_utils.get(api.nvim_get_current_buf(), args)

  if args and args.fargs and #args.fargs > 0 then
    local prompt = args.fargs[1]:lower()

    -- Check if the adapter is available
    adapter = config.adapters[prompt]

    if not adapter then
      if prompt == "add" then
        return M.add(args)
      elseif prompt == "toggle" then
        return M.toggle()
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
M.cmd = function(args)
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
M.toggle = function()
  local chat = M.last_chat()

  if not chat then
    return M.chat()
  end

  if chat.ui:is_visible() then
    return chat.ui:hide()
  end

  chat.context = context_utils.get(api.nvim_get_current_buf())
  M.close_last_chat()
  chat.ui:open()
end

---Return a chat buffer
---@param bufnr? integer
---@return CodeCompanion.Chat|table
M.buf_get_chat = function(bufnr)
  return require("codecompanion.strategies.chat").buf_get_chat(bufnr)
end

---Get the last chat buffer
---@return CodeCompanion.Chat|nil
M.last_chat = function()
  return require("codecompanion.strategies.chat").last_chat()
end

---Close the last chat buffer
---@return nil
M.close_last_chat = function()
  return require("codecompanion.strategies.chat").close_last_chat()
end

---Show the action palette
---@param args table
---@return nil
M.actions = function(args)
  local context = context_utils.get(api.nvim_get_current_buf(), args)
  return require("codecompanion.actions").launch(context, args)
end

---Setup the plugin
---@param opts? table
---@return nil
M.setup = function(opts)
  if vim.fn.has("nvim-0.10.0") == 0 then
    return api.nvim_err_writeln("CodeCompanion.nvim requires Neovim 0.10.0+")
  end

  -- Setup the plugin's config
  config.setup(opts)
  if opts and opts.adapters then
    require("codecompanion.utils.adapters").extend(config.adapters, opts.adapters)
  end

  -- Create the user commands
  local cmds = require("codecompanion.commands")
  for _, cmd in ipairs(cmds) do
    api.nvim_create_user_command(cmd.cmd, cmd.callback, cmd.opts)
  end

  -- Set the highlight groups
  api.nvim_set_hl(0, "CodeCompanionChatHeader", { link = "@markup.heading.2.markdown", default = true })
  api.nvim_set_hl(0, "CodeCompanionChatSeparator", { link = "@punctuation.special.markdown", default = true })
  api.nvim_set_hl(0, "CodeCompanionChatTokens", { link = "Comment", default = true })
  api.nvim_set_hl(0, "CodeCompanionChatAgent", { link = "Constant", default = true })
  api.nvim_set_hl(0, "CodeCompanionChatTool", { link = "Special", default = true })
  api.nvim_set_hl(0, "CodeCompanionChatVariable", { link = "Identifier", default = true })
  api.nvim_set_hl(0, "CodeCompanionVirtualText", { link = "Comment", default = true })

  -- Setup syntax highlighting for the chat buffer
  local group = "codecompanion.syntax"
  api.nvim_create_augroup(group, { clear = true })
  api.nvim_create_autocmd("FileType", {
    pattern = "codecompanion",
    group = group,
    callback = vim.schedule_wrap(function()
      vim.iter(config.strategies.chat.variables):each(function(name, var)
        vim.cmd.syntax('match CodeCompanionChatVariable "#' .. name .. '"')
        if var.opts and var.opts.has_params then
          vim.cmd.syntax('match CodeCompanionChatVariable "#' .. name .. ':\\d\\+-\\?\\d\\+"')
        end
      end)
      vim.iter(config.strategies.chat.agents.tools):each(function(name, _)
        vim.cmd.syntax('match CodeCompanionChatTool "@' .. name .. '"')
      end)
      vim
        .iter(config.strategies.chat.agents)
        :filter(function(name)
          return name ~= "tools"
        end)
        :each(function(name, _)
          vim.cmd.syntax('match CodeCompanionChatAgent "@' .. name .. '"')
        end)
    end),
  })

  -- TODO: Move to chat buffer
  config.INFO_NS = api.nvim_create_namespace("CodeCompanion-info")
  config.ERROR_NS = api.nvim_create_namespace("CodeCompanion-error")

  local diagnostic_config = {
    underline = false,
    virtual_text = {
      spacing = 2,
      severity = { min = vim.diagnostic.severity.INFO },
    },
    signs = false,
  }
  vim.diagnostic.config(diagnostic_config, config.INFO_NS)
  vim.diagnostic.config(diagnostic_config, config.ERROR_NS)

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

  -- Setup completion for blink.cmp and cmp
  local has_cmp, cmp = pcall(require, "cmp")
  local has_blink, blink = pcall(require, "blink.cmp")
  if has_blink then
    pcall(function()
      blink.add_provider("codecompanion", {
        name = "CodeCompanion",
        module = "codecompanion.providers.completion.blink",
        enabled = true,
        score_offset = 10,
      })
    end)
    pcall(function()
      blink.add_filetype_source("codecompanion", "codecompanion")
    end)
  -- We need to check for blink alongside cmp as blink.compat has a module that
  -- is detected by a require("cmp") call and a lot of users have it installed
  -- Reference: https://github.com/olimorris/codecompanion.nvim/discussions/501
  elseif has_cmp and not has_blink then
    local completion = "codecompanion.providers.completion.cmp"
    cmp.register_source("codecompanion_models", require(completion .. ".models").new(config))
    cmp.register_source("codecompanion_slash_commands", require(completion .. ".slash_commands").new(config))
    cmp.register_source("codecompanion_tools", require(completion .. ".tools").new(config))
    cmp.register_source("codecompanion_variables", require(completion .. ".variables").new())
    cmp.setup.filetype("codecompanion", {
      enabled = true,
      sources = vim.list_extend({
        { name = "codecompanion_models" },
        { name = "codecompanion_slash_commands" },
        { name = "codecompanion_tools" },
        { name = "codecompanion_variables" },
      }, cmp.get_config().sources),
    })
  end

  -- Capture the last terminal buffer
  _G.codecompanion_last_terminal = nil
  api.nvim_create_autocmd("TermEnter", {
    desc = "Capture the last terminal buffer",
    callback = function()
      local bufnr = api.nvim_get_current_buf()
      if vim.bo[bufnr].buftype == "terminal" then
        _G.codecompanion_last_terminal = bufnr
      end
    end,
  })

  vim.treesitter.language.register("markdown", "codecompanion")
end

return M
