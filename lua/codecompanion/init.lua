local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils.context")
local api = vim.api

---@class CodeCompanion
local M = {}

M.pre_defined_prompts = {}
M.config = require("codecompanion.config")

---Prompt the LLM from within the current buffer
---@param args table
---@return nil|CodeCompanion.Inline
M.inline = function(args)
  local context = util.get_context(api.nvim_get_current_buf(), args)

  return require("codecompanion.strategies.inline")
    .new({
      context = context,
      prompts = {
        {
          role = "system",
          tag = "system_tag",
          content = function()
            return "I want you to act as a senior "
              .. context.filetype
              .. " developer. I will ask you specific questions and I want you to return raw code only (no codeblocks and no explanations). If you can't respond with code, respond with nothing."
          end,
        },
      },
    })
    :start(args)
end

---Run the prompt that the user initiated from the command line
---@param prompt table The prompt to resolve from the command
---@param args table The arguments that were passed to the command
---@return CodeCompanion.Strategies
M.run_pre_defined_prompts = function(prompt, args)
  local context = util.get_context(api.nvim_get_current_buf(), args)
  local item = M.pre_defined_prompts[prompt]

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
  local chat = _G.codecompanion_last_chat_buffer

  if not chat then
    return vim.notify("[CodeCompanion.nvim]\nNo chat buffer found", vim.log.levels.WARN)
  end
  if not M.config.opts.send_code then
    return vim.notify("[CodeCompanion.nvim]\nSending of code to an LLM is currently disabled", vim.log.levels.WARN)
  end

  local context = util.get_context(api.nvim_get_current_buf(), args)
  local content = table.concat(context.lines, "\n")

  chat:append({
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
  local context = util.get_context(api.nvim_get_current_buf(), args)

  if args and args.fargs then
    adapter = M.config.adapters[args.fargs[1]]
  end

  local chat = require("codecompanion.strategies.chat").new({
    context = context,
    adapter = adapter,
  })

  if not chat then
    return vim.notify("[CodeCompanion.nvim]\nNo chat strategy found", vim.log.levels.WARN)
  end

  ui.scroll_to_end(0)
end

---Toggle the chat buffer
---@return nil
M.toggle = function()
  local chat = _G.codecompanion_last_chat_buffer
  if not chat then
    return M.chat()
  end

  if chat:visible() then
    return chat:hide()
  end

  -- Update the context of the chat object
  local context = util.get_context(api.nvim_get_current_buf())
  chat.context = context

  chat:open()
end

---@param bufnr nil|integer
---@return nil|CodeCompanion.Chat
M.buf_get_chat = function(bufnr)
  return require("codecompanion.strategies.chat").buf_get_chat(bufnr)
end

local _cached_actions = {}
---Show the action palette
---@param args table
---@return nil
M.actions = function(args)
  local actions = require("codecompanion.actions")
  local context = util.get_context(api.nvim_get_current_buf(), args)

  local function picker(items, opts, callback)
    opts = opts or {}
    opts.prompt = opts.prompt or "Select an option"
    opts.columns = opts.columns or { "name", "strategy", "description" }

    require("codecompanion.utils.ui").selector(items, {
      prompt = opts.prompt,
      width = M.config.display.action_palette.width,
      height = M.config.display.action_palette.height,
      format = function(item)
        local formatted_item = {}
        for _, column in ipairs(opts.columns) do
          if item[column] ~= nil then
            if type(item[column]) == "function" then
              table.insert(formatted_item, item[column](context))
            else
              table.insert(formatted_item, item[column] or "")
            end
          end
        end
        return formatted_item
      end,
      callback = callback,
    })
  end

  local function selection(item)
    if item.picker and type(item.picker.items) == "table" then
      local picker_opts = {
        prompt = item.picker.prompt,
        columns = item.picker.columns,
      }
      return picker(actions.validate(item.picker.items, context), picker_opts, selection)
    elseif item.picker and type(item.picker.items) == "function" then
      local picker_opts = {
        prompt = item.picker.prompt,
        columns = item.picker.columns,
      }
      picker(actions.validate(item.picker.items(context), context), picker_opts, selection)
    elseif item and type(item.callback) == "function" then
      return item.callback(context)
    else
      local Strategy = require("codecompanion.strategies")
      return Strategy.new({
        context = context,
        selected = item,
      }):start(item.strategy)
    end
  end

  if not next(_cached_actions) then
    if M.config.opts.use_default_actions then
      for _, action in ipairs(actions.static.actions) do
        if action.opts and action.opts.enabled == false then
          goto continue
        else
          table.insert(_cached_actions, action)
        end
        ::continue::
      end
    end
    if M.config.actions and #M.config.actions > 0 then
      for _, action in ipairs(M.config.actions) do
        table.insert(_cached_actions, action)
      end
    end
  end

  local items = actions.validate(_cached_actions, context)

  if items and #items == 0 then
    return vim.notify(
      "[CodeCompanion.nvim]\nNo actions set. Please create some in your config or turn on the defaults",
      vim.log.levels.WARN
    )
  end

  picker(items, { prompt = "CodeCompanion actions", columns = { "name", "strategy", "description" } }, selection)
end

---Setup the plugin
---@param opts nil|table
---@return nil
M.setup = function(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Set the highlight groups
  local hg = M.config.display.chat.highlights
  api.nvim_set_hl(0, "CodeCompanionTokens", { link = hg.tokens, default = true })
  api.nvim_set_hl(0, "CodeCompanionVirtualText", { link = hg.virtual_text, default = true })
  api.nvim_set_hl(0, "CodeCompanionVirtualTextAgents", { link = hg.virtual_text_agents, default = true })
  api.nvim_set_hl(0, "CodeCompanionChatVariable", { link = hg.variables, default = true })

  -- Setup syntax highlighting for the chat buffer
  local group = "codecompanion.syntax"
  vim.api.nvim_create_augroup(group, { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "codecompanion",
    group = group,
    callback = vim.schedule_wrap(function()
      vim.cmd.syntax('match CodeCompanionChatVariable "#buffer"')
      vim.cmd.syntax('match CodeCompanionChatVariable "#buffers"')
      vim.cmd.syntax('match CodeCompanionChatVariable "#editor"')
    end),
  })

  -- Handle custom adapter config
  if opts and opts.adapters then
    for name, adapter in pairs(opts.adapters) do
      if M.config.adapters[name] then
        if type(adapter) == "table" then
          M.config.adapters[name] = adapter
          if adapter.schema then
            M.config.adapters[name].schema =
              vim.tbl_deep_extend("force", M.config.adapters[name].schema, adapter.schema)
          end
        end
      end
    end
  end

  -- Setup the pre-defined prompts
  local prompts = require("codecompanion.utils.prompts").new(M.config.action_prompts):setup()
  for name, prompt in pairs(prompts.prompts) do
    if prompt.opts.shortcut then
      prompt.name = name
      M.pre_defined_prompts[prompt.opts.shortcut] = prompt
    end
  end

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

  local log = require("codecompanion.utils.log")
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

  vim.treesitter.language.register("markdown", "codecompanion")
end

return M
