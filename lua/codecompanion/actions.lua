local config = require("codecompanion").config
local utils = require("codecompanion.utils.util")

local M = {}

M.static = {}

local send_code = function(context)
  local text = require("codecompanion.helpers.code").get_code(context.start_line, context.end_line)

  return "I have the following code:\n\n```" .. context.filetype .. "\n" .. text .. "\n```\n\n"
end

M.validate = function(items, context)
  local validated_items = {}
  local mode = context.mode:lower()

  for _, item in ipairs(items) do
    if item.condition and type(item.condition) == "function" then
      if item.condition(context) then
        table.insert(validated_items, item)
      end
    elseif item.opts and item.opts.modes then
      if utils.contains(item.opts.modes, mode) then
        table.insert(validated_items, item)
      end
    else
      table.insert(validated_items, item)
    end
  end

  return validated_items
end

M.static.actions = {
  {
    name = "Chat",
    strategy = "chat",
    description = "Open a chat buffer to converse with an LLM",
    type = nil,
    opts = {
      stop_context_insertion = true,
    },
    prompts = {
      n = function()
        return require("codecompanion").chat()
      end,
      v = {
        {
          role = "system",
          content = function(context)
            return "I want you to act as a senior "
              .. context.filetype
              .. " developer. I will give you specific code examples and ask you questions. I want you to advise me with explanations and code examples."
          end,
        },
        {
          role = "user",
          contains_code = true,
          content = function(context)
            return send_code(context)
          end,
        },
      },
    },
  },
  {
    name = "Prompts ...",
    strategy = " ",
    description = "Pre-defined prompts to help you code",
    condition = function()
      return config.prompts and utils.count(config.prompts) > 0
    end,
    picker = {
      prompt = "Prompts",
      items = function(context)
        local prompts = {}

        local sort_index = true
        for name, prompt in pairs(config.prompts) do
          if not config.use_default_prompts and prompt.opts and prompt.opts.default_prompt then
            goto continue
          end

          if not prompt.opts or not prompt.opts.index then
            sort_index = false
          end

          if type(prompt.name_f) == "function" then
            name = prompt.name_f(context)
          end

          local description = prompt.description
          if type(prompt.description) == "function" then
            description = prompt.description(context)
          end
          if prompt.opts and prompt.opts.shortcut then
            description = "(@" .. prompt.opts.shortcut .. ") " .. description
          end

          table.insert(prompts, {
            name = name,
            strategy = prompt.strategy,
            description = description,
            opts = prompt.opts,
            prompts = prompt.prompts,
          })

          ::continue::
        end

        if sort_index then
          table.sort(prompts, function(a, b)
            return a.opts.index < b.opts.index
          end)
        end

        return prompts
      end,
    },
  },
  {
    name = "Open chats ...",
    strategy = " ",
    description = "Your currently open chats",
    condition = function()
      return _G.codecompanion_chats and utils.count(_G.codecompanion_chats) > 0
    end,
    picker = {
      prompt = "Select a chat",
      items = function()
        local ui = require("codecompanion.utils.ui")
        local chats = {}

        for bufnr, chat in pairs(_G.codecompanion_chats) do
          table.insert(chats, {
            name = chat.name,
            strategy = "chat",
            description = chat.description,
            callback = function()
              _G.codecompanion_chats[bufnr] = nil
              chat.chat:open()
              ui.buf_scroll_to_end(bufnr)
            end,
          })
        end

        return chats
      end,
    },
  },
  {
    name = "Agents ...",
    strategy = " ",
    description = "Use the built-in agents to help you code",
    condition = function()
      local agents = config.agents
      local i = 0
      for _, agent in pairs(agents) do
        if agent.enabled then
          i = i + 1
        end
      end
      return i > 0
    end,
    picker = {
      prompt = "Chat with an Agent",
      items = function()
        local agents = {}

        for id, agent in pairs(config.agents) do
          if agent.enabled then
            local t
            if agent.location then
              t = require(agent.location .. "." .. id)
            else
              t = require("codecompanion.agents." .. id)
            end

            -- Form the prompts
            local prompts = {}
            for _, prompt in ipairs(t.prompts) do
              table.insert(prompts, {
                role = prompt.role,
                content = function()
                  return type(prompt.content) == "function" and prompt.content(t.schema) or "\n \n"
                end,
              })
            end

            table.insert(agents, {
              name = agent.name,
              strategy = "agent",
              description = agent.description or nil,
              prompts = prompts,
            })
          end
        end

        return agents
      end,
    },
  },
  {
    name = "Workflows ...",
    strategy = " ",
    description = "Workflows to improve the performance of your LLM",
    picker = {
      prompt = "Select a workflow",
      items = {
        {
          name = "Code a feature - Outline, draft, consider and then revise",
          callback = function(context)
            local agent = require("lua.codecompanion.workflow")
            return agent
              .new({
                context = context,
                strategy = "chat",
              })
              :workflow({
                {
                  role = "system",
                  content = "You carefully provide accurate, factual, thoughtful, nuanced answers, and are brilliant at reasoning. If you think there might not be a correct answer, you say so. Always spend a few sentences explaining background context, assumptions, and step-by-step thinking BEFORE you try to answer a question. Don't be verbose in your answers, but do provide details and examples where it might help the explanation. You are an expert software engineer for the "
                    .. context.filetype
                    .. " language.",
                  start = true,
                },
                {
                  condition = function()
                    return context.is_visual
                  end,
                  contains_code = true,
                  role = "user",
                  content = "Here is some relevant context: " .. send_code(context),
                  start = true,
                },
                {
                  role = "user",
                  content = "I want you to help me code a feature. Before we write any code let's outline how we'll architect and implement the feature with the context you already have. The feature I'd like to add is ",
                  start = true,
                },
                {
                  role = "user",
                  content = "Thanks. Now let's draft the code for the feature.",
                  auto_submit = true,
                },
                {
                  role = "user",
                  content = "Great. Now let's consider the code. I'd like you to check it carefully for correctness, style, and efficiency, and give constructive criticism for how to improve it.",
                  auto_submit = true,
                },
                {
                  role = "user",
                  content = "Thanks. Now let's revise the code based on the feedback, without additional explanations.",
                  auto_submit = true,
                },
              })
          end,
        },
        {
          name = "Refactor some code - Outline, draft, consider and then revise",
          callback = function(context)
            local agent = require("lua.codecompanion.workflow")
            return agent
              .new({
                context = context,
                strategy = "chat",
              })
              :workflow({
                {
                  role = "system",
                  content = "You carefully provide accurate, factual, thoughtful, nuanced answers, and are brilliant at reasoning. If you think there might not be a correct answer, you say so. Always spend a few sentences explaining background context, assumptions, and step-by-step thinking BEFORE you try to answer a question. Don't be verbose in your answers, but do provide details and examples where it might help the explanation. You are an expert software engineer for the "
                    .. context.filetype
                    .. " language.",
                  start = true,
                },
                {
                  condition = function()
                    return context.is_visual
                  end,
                  contains_code = true,
                  role = "user",
                  content = "Here is some relevant context: " .. send_code(context),
                  start = true,
                },
                {
                  role = "user",
                  content = "I want you to help me with a refactor. Before we write any code let's outline how we'll architect and implement the code with the context you already have. What I'm looking to achieve is ",
                  start = true,
                },
                {
                  role = "user",
                  content = "Thanks. Now let's draft the code for the refactor.",
                  auto_submit = true,
                },
                {
                  role = "user",
                  content = "Great. Now let's consider the code. I'd like you to check it carefully for correctness, style, and efficiency, and give constructive criticism for how to improve it.",
                  auto_submit = true,
                },
                {
                  role = "user",
                  content = "Thanks. Now let's revise the code based on the feedback, without additional explanations.",
                  auto_submit = true,
                },
              })
          end,
        },
      },
    },
  },
  {
    name = "Load saved chats ...",
    strategy = " ",
    description = "Load your previously saved chats",
    condition = function()
      local saved_chats = require("codecompanion.strategies.saved_chats")
      return saved_chats:has_chats()
    end,
    picker = {
      prompt = "Load chats",
      items = function()
        local saved_chats = require("codecompanion.strategies.saved_chats")
        local items = saved_chats:list({ sort = true })

        local chats = {}

        for _, chat in pairs(items) do
          table.insert(chats, {
            name = chat.tokens,
            strategy = chat.filename,
            description = chat.dir,
            callback = function()
              return saved_chats
                .new({
                  filename = chat.filename,
                })
                :load(chat)
            end,
          })
        end

        return chats
      end,
    },
  },
}

return M
