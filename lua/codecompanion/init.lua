local context_utils = require("codecompanion.utils.context")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils.util")

local api = vim.api

---@class CodeCompanion
---@field chat fun(args?: table): nil
---@field config table
---@field buf_get_chat fun(bufnr: integer): CodeCompanion.Chat|table
local M = {}

M.slash_cmds = {}
M.config = require("codecompanion.config")

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
          role = "system",
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

---Run the prompt that the user initiated from the command line
---@param prompt table The prompt to resolve from the command
---@param args table The arguments that were passed to the command
---@return nil
M.run_inline_slash_cmds = function(prompt, args)
  log:trace("Running slash_cmd")
  local context = context_utils.get(api.nvim_get_current_buf(), args)
  local item = M.slash_cmds[prompt]

  -- A user may add a prompt after calling the slash command
  if item.opts.user_prompt and args.user_prompt then
    log:trace("Adding custom user prompt via slash_cmd")
    item.opts.user_prompt = args.user_prompt
  end

  return require("codecompanion.strategies")
    .new({
      context = context,
      selected = item,
    })
    :start(item.strategy)
end

---Add visually selected code to the current chat buffer
---@param args table
---@return nil
M.add = function(args)
  local chat = M.last_chat()

  if not chat then
    return log:warn("No chat buffer found")
  end
  if not M.config.opts.send_code then
    return log:warn("Sending of code to an LLM has been disabled")
  end

  local context = context_utils.get(api.nvim_get_current_buf(), args)
  local content = table.concat(context.lines, "\n")

  chat:append_to_buf({
    role = "user",
    content = "Here is some code from "
      .. context.filename
      .. ":\n\n```"
      .. context.filetype
      .. "\n"
      .. content
      .. "\n```\n",
  })
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
    adapter = M.config.adapters[prompt]

    if not adapter then
      if prompt == "add" then
        return M.add(args)
      elseif prompt == "toggle" then
        return M.toggle()
      else
        table.insert(messages, {
          role = "user",
          content = args.args,
        })
      end
    end
  end

  local has_messages = util.count(messages) > 0

  return require("codecompanion.strategies.chat").new({
    context = context,
    adapter = adapter,
    messages = has_messages and messages or nil,
    auto_submit = has_messages,
  })
end

---Toggle the chat buffer
---@return nil
M.toggle = function()
  local chat = M.last_chat()

  if not chat then
    return M.chat()
  end

  if chat:is_visible() then
    return chat:hide()
  end

  chat.context = context_utils.get(api.nvim_get_current_buf())
  M.close_last_chat()
  chat:open()
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
  return require("codecompanion.actions").launch(context)
end

---Setup the plugin
---@param opts nil|table
---@return nil
M.setup = function(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  if opts and opts.adapters then
    require("codecompanion.utils.adapters").extend(M.config.adapters, opts.adapters)
  end

  -- Set the highlight groups
  api.nvim_set_hl(0, "CodeCompanionChatHeader", { link = "@markup.heading.2.markdown", default = true })
  api.nvim_set_hl(0, "CodeCompanionChatSeparator", { link = "@punctuation.special.markdown", default = true })
  api.nvim_set_hl(0, "CodeCompanionChatTokens", { link = "Comment", default = true })
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
      for name, var in pairs(M.config.strategies.chat.variables) do
        vim.cmd.syntax('match CodeCompanionChatVariable "#' .. name .. '"')
        if var.opts and var.opts.has_params then
          vim.cmd.syntax('match CodeCompanionChatVariable "#' .. name .. ':\\d\\+-\\?\\d\\+"')
        end
      end
      for name, _ in pairs(M.config.strategies.agent.tools) do
        vim.cmd.syntax('match CodeCompanionChatTool "@' .. name .. '"')
      end
    end),
  })

  -- Setup the inline slash commands the keymaps from the prompt library
  local prompt_library = require("codecompanion.actions.prompt_library")
  prompt_library.setup_keymaps(M.config)
  M.slash_cmds = prompt_library.setup_inline_slash_commands(M.config)

  -- TODO: Move to chat buffer
  M.config.INFO_NS = api.nvim_create_namespace("CodeCompanion-info")
  M.config.ERROR_NS = api.nvim_create_namespace("CodeCompanion-error")

  local diagnostic_config = {
    underline = false,
    virtual_text = {
      spacing = 2,
      severity = { min = vim.diagnostic.severity.INFO },
    },
    signs = false,
  }
  vim.diagnostic.config(diagnostic_config, M.config.INFO_NS)
  vim.diagnostic.config(diagnostic_config, M.config.ERROR_NS)

  log.set_root(log.new({
    handlers = {
      {
        type = "echo",
        level = vim.log.levels.WARN,
      },
      {
        type = "file",
        filename = "codecompanion.log",
        level = vim.log.levels[M.config.opts.log_level],
      },
    },
  }))

  -- Setup cmp
  local has_cmp, cmp = pcall(require, "cmp")
  if has_cmp then
    cmp.register_source("codecompanion_tools", require("cmp_codecompanion.tools").new(M.config))
    cmp.register_source("codecompanion_variables", require("cmp_codecompanion.variables").new())
    cmp.register_source("codecompanion_slash_commands", require("cmp_codecompanion.slash_commands").new())
    cmp.register_source("codecompanion_models", require("cmp_codecompanion.models").new(M.config))
    cmp.setup.filetype("codecompanion", {
      enabled = true,
      sources = {
        { name = "codecompanion_tools" },
        { name = "codecompanion_variables" },
        { name = "codecompanion_slash_commands" },
        { name = "codecompanion_models" },
      },
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
