local codecompanion = require("codecompanion")

local function send_code(context)
  local text = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)

  return "I have the following code:\n\n```" .. context.filetype .. "\n" .. text .. "\n```\n\n"
end

return {
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
        return codecompanion.chat()
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
      return #codecompanion.buf_get_chat() > 0
    end,
    picker = {
      prompt = "Select a chat",
      items = function()
        local loaded_chats = codecompanion.buf_get_chat()
        local open_chats = {}

        for _, data in ipairs(loaded_chats) do
          table.insert(open_chats, {
            name = data.name,
            strategy = "chat",
            description = data.description,
            callback = function()
              codecompanion.close_last_chat()
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
