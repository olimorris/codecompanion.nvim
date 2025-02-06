# Creating Workflows

Workflows in CodeCompanion, are simply successive prompts which are sent to the LLM in a turn-based manner. This allows for actions such as reflection and planning to be easily implemented into your workflow. When combined with tools, they can be used to automate certain activities like editing files and then running your tests.

I fully recommend reading [Issue 242](https://www.deeplearning.ai/the-batch/issue-242/) of The Batch to understand the origin of workflows but note that they were included in the plugin as an early form of [Chain-of-thought](https://en.wikipedia.org/wiki/Prompt_engineering#Chain-of-thought) prompting, via the use of reflection and planning prompts.

## How They Work

Before we cover some more impressive and complex examples, it's important to understand how workflows have been implemented in the plugin.

When initiated from the [Action Palette](/usage/action-palette), workflows attach themselves to a [chat buffer](/usage/chat-buffer/index) via a notion of a _subscription_. That is, the workflow has subscribed to all events that take place in the chat buffer. After the LLM sends its response, the chat buffer will trigger an event on the subscription class. This will execute a callback which has been defined in the workflow itself (often times this is simply a prompt to place in the chat buffer), and the event will duly be deleted from the subscription to prevent it from executing again.

## Your First Workflow

Workflows are setup in exactly the same way as prompts in the [prompt library](/extending/prompts). Take the `code workflow` as an example:

```lua
["Code workflow"] = {
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
        role = constants.SYSTEM_ROLE,
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
        role = constants.USER_ROLE,
        content = "I want you to ",
        opts = {
          auto_submit = false,
        },
      },
    },
    -- This is the second group of prompts
    {
      {
        role = constants.USER_ROLE,
        content = "Great. Now let's consider your code. I'd like you to check it carefully for correctness, style, and efficiency, and give constructive criticism for how to improve it.",
        opts = {
          auto_submit = false,
        },
      },
    },
    -- This is the final group of prompts
    {
      {
        role = constants.USER_ROLE,
        content = "Thanks. Now let's revise the code based on the feedback, without additional explanations.",
        opts = {
          auto_submit = false,
        },
      },
    },
  },
},
```

You'll notice that the comments use the notion of "groups". These are collections of prompts which are added to a chat buffer in a timely manner. Infact, the second group will only be added once the LLM has responded to the first group...and so on.

The `auto_submit` option allows you to automatically send prompts to an LLM, saving you a keypress. Please note that there is default delay of 2s (which can be changed as per the [config.lua](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua) file under `opts.submit_delay`) to avoid triggering a rate limit block on the LLM's endpoint.

## Combining Workflows and Tools

Now let's explore a more complex example: the `Testing workflow` that comes with the plugin.

This workflow is unique in that it combines with the [@cmd_runner](/usage/chat-buffer/agents#cmd-runner) tool to understand the status of any tests that have been executed. If there were any failures, then the LLM will be notified and prompted to make any updates via the [@editor](/usage/chat-buffer/agents#editor) tool. If the tests were all green, then no further prompting is made.

## Other Options

There are also a number of options which haven't been covered in the example prompts above:

**Specifying an Adapter**

You can specify a specific adapter for a workflow prompt:

```lua
["Workflow"] = {
  strategy = "workflow",
  description = "My workflow",
  opts = {
    adapter = "openai", -- Always use the OpenAI adapter for this workflow
  },
  -- Prompts go here
},
```

**Persistent Prompts**

By default, all workflow prompts are of the type `once`. That is, they are consumed once and then removed. However, this can be changed:

```lua
["A Cool Workflow"] = {
  strategy = "workflow",
  description = "My cool workflow",
  prompts = {
    {
      -- Some first prompt
    },
    {
      {
        role = constants.USER_ROLE,
        content = "This prompt will never go away!",
        type = "persistent",
        opts = {
          auto_submit = false,
        },
      },
    },
  },
},
```

Note that persistent prompts are not available for the first prompt group.

