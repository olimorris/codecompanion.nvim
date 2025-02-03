return {
  strategy = "workflow",
  description = "Use a workflow to guide an LLM in writing code",
  opts = {
    index = 4,
    is_default = true,
    short_name = "workflow",
  },
  prompts = {
    {
      -- We can group prompts together to make a workflow
      -- This is the first prompt in the workflow
      {
        role = "system",
        content = function(context)
          return string.format(
            "You carefully provide accurate, factual, thoughtful, nuanced answers, and are brilliant at reasoning. If you think there might not be a correct answer, you say so. Always spend a few sentences explaining background context, assumptions, and step-by-step thinking BEFORE you try to answer a question. Don't be verbose in your answers, but do provide details and examples where it might help the explanation. You are an expert software engineer for the %s language",
            context.filetype
          )
        end,
        opts = {
          visible = false,
        },
      },
      {
        role = "user",
        content = "I want you to ",
        opts = {
          auto_submit = false,
        },
      },
    },
    -- This is the second group of prompts
    {
      {
        role = "user",
        content = "Great. Now let's consider your code. I'd like you to check it carefully for correctness, style, and efficiency, and give constructive criticism for how to improve it.",
        opts = {
          auto_submit = true,
        },
      },
    },
    -- This is the final group of prompts
    {
      {
        role = "user",
        content = "Thanks. Now let's revise the code based on the feedback, without additional explanations.",
        opts = {
          auto_submit = true,
        },
      },
    },
  },
}
