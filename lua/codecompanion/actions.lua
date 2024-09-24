local config = require("codecompanion").config
local utils = require("codecompanion.utils.util")

local M = {}

M.static = {}

local send_code = function(context)
  local text = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)

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
      index = 1,
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
          content = function(context)
            return send_code(context)
          end,
          opts = {
            contains_code = true,
          },
        },
      },
    },
  },
  {
    name = "Open chats ...",
    strategy = " ",
    description = "Your currently open chats",
    opts = {
      index = 2,
      stop_context_insertion = true,
    },
    condition = function()
      return #require("codecompanion").buf_get_chat() > 0
    end,
    picker = {
      prompt = "Select a chat",
      items = function()
        local loaded_chats = require("codecompanion").buf_get_chat()
        local open_chats = {}

        for _, data in ipairs(loaded_chats) do
          table.insert(open_chats, {
            name = data.name,
            strategy = "chat",
            description = data.description,
            callback = function()
              require("codecompanion").close_last_chat()
              data.chat:open()
            end,
          })
        end

        return open_chats
      end,
    },
  },
  {
    name = "Workflows ...",
    strategy = " ",
    description = "Workflows to improve the performance of your LLM",
    opts = {
      index = 10,
    },
    picker = {
      prompt = "Select a workflow",
      items = {
        {
          name = "Code a feature - Outline, draft, consider and then revise",
          callback = function(context)
            local agent = require("codecompanion.workflow")
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
                  opts = {
                    start = true,
                  },
                },
                {
                  condition = function()
                    return context.is_visual
                  end,
                  role = "user",
                  content = "Here is some relevant context: " .. send_code(context),
                  opts = {
                    contains_code = true,
                    start = true,
                  },
                },
                {
                  role = "user",
                  content = "I want you to help me code a feature. Before we write any code let's outline how we'll architect and implement the feature with the context you already have. The feature I'd like to add is ",
                  opts = {
                    start = true,
                  },
                },
                {
                  role = "user",
                  content = "Thanks. Now let's draft the code for the feature.",
                  opts = {
                    auto_submit = true,
                  },
                },
                {
                  role = "user",
                  content = "Great. Now let's consider the code. I'd like you to check it carefully for correctness, style, and efficiency, and give constructive criticism for how to improve it.",
                  opts = {
                    auto_submit = true,
                  },
                },
                {
                  role = "user",
                  content = "Thanks. Now let's revise the code based on the feedback, without additional explanations.",
                  opts = {
                    auto_submit = true,
                  },
                },
              })
          end,
        },
        {
          name = "Refactor some code - Outline, draft, consider and then revise",
          callback = function(context)
            local agent = require("codecompanion.workflow")
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
                  opts = {
                    start = true,
                  },
                },
                {
                  condition = function()
                    return context.is_visual
                  end,
                  role = "user",
                  content = "Here is some relevant context: " .. send_code(context),
                  opts = {
                    contains_code = true,
                    start = true,
                  },
                },
                {
                  role = "user",
                  content = "I want you to help me with a refactor. Before we write any code let's outline how we'll architect and implement the code with the context you already have. What I'm looking to achieve is ",
                  opts = {
                    start = true,
                  },
                },
                {
                  role = "user",
                  content = "Thanks. Now let's draft the code for the refactor.",
                  opts = {
                    auto_submit = true,
                  },
                },
                {
                  role = "user",
                  content = "Great. Now let's consider the code. I'd like you to check it carefully for correctness, style, and efficiency, and give constructive criticism for how to improve it.",
                  opts = {
                    auto_submit = true,
                  },
                },
                {
                  role = "user",
                  content = "Thanks. Now let's revise the code based on the feedback, without additional explanations.",
                  opts = {
                    auto_submit = true,
                  },
                },
              })
          end,
        },
      },
    },
  },
}

local prompts = {}

--- Add default prompts to the actions
M.add_default_prompt_library = function(context)
  if config.prompt_library and utils.count(config.prompt_library) > 0 then
    local sort_index = true

    for name, prompt in pairs(config.prompt_library) do
      if not config.opts.use_default_prompt_library and (prompt.opts and prompt.opts.is_default) then
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
      if prompt.opts and prompt.opts.slash_cmd then
        description = "(/" .. prompt.opts.slash_cmd .. ") " .. description
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

    for _, prompt in ipairs(prompts) do
      table.insert(M.static.actions, prompt)
    end
  end
end

return M
