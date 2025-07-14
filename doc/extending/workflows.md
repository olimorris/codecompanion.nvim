# Creating Workflows

Workflows in CodeCompanion, are successive prompts which can be automatically sent to the LLM in a turn-based manner. This allows for actions such as reflection and planning to be easily implemented into your workflow. They can be combined with tools to create agentic workflows, which could be used to automate common activities like editing files and then running a test suite.

I fully recommend reading [Issue 242 of The Batch](https://www.deeplearning.ai/the-batch/issue-242/) to understand the origin of workflows. They were originally [implemented](https://github.com/olimorris/codecompanion.nvim/commit/73e5a27075749b3ff60cfc796438d302d4b08715) in the plugin as an early form of [Chain-of-thought](https://en.wikipedia.org/wiki/Prompt_engineering#Chain-of-thought) prompting, via the use of reflection and planning prompts.

## How They Work

Before showcasing some examples, it's important to understand how workflows have been implemented in the plugin.

When initiated from the [Action Palette](/usage/action-palette), workflows attach themselves to a [chat buffer](/usage/chat-buffer/index) via the notion of a _subscription_. That is, the workflow has subscribed to the conversation and dataflow that's taking place in the chat buffer. After the LLM sends a response, the chat buffer will trigger an event on the subscription class. This will execute a callback which has been defined in the workflow itself (often times this is simply a text prompt), and the event will duly be deleted from the subscription to prevent it from being executed again.

## Simple Workflows

Workflows are setup in exactly the same way as prompts in the [prompt library](/extending/prompts). Take the `code workflow` as an example:

```lua
["Code workflow"] = {
  strategy = "workflow",
  description = "Use a workflow to guide an LLM in writing code",
  opts = {
    index = 4,
    is_default = true,
    short_name = "cw",
  },
  prompts = {
    {
      -- We can group prompts together to make a workflow
      -- This is the first prompt in the workflow
      -- Everything in this group is added to the chat buffer in one batch
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

The `auto_submit` option allows you to automatically send prompts to an LLM, saving you a keypress. Please note that there is default delay of 2s (which can be changed as per the [config.lua](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua) file under `opts.submit_delay`) to avoid triggering a rate limit block on an LLM's endpoint.

## Agentic Workflows

By combining a workflow with tools, we can use an LLM to act as an Agent and do some impressive things!

A great example of that is the `Edit<->Test` workflow that come with the plugin. This workflow asks the LLM to edit code in a buffer and then run a test suite, feeding the output back to the LLM to then make future edits if required.

Let's breakdown the prompts in that workflow:

```lua
prompts = {
  {
    {
      name = "Setup Test",
      role = constants.USER_ROLE,
      opts = { auto_submit = false },
      content = function()
        -- Leverage auto_tool_mode which disables the requirement of approvals and automatically saves any edited buffer
        vim.g.codecompanion_auto_tool_mode = true

        -- Some clear instructions for the LLM to follow
        return [[### Instructions

Your instructions here

### Steps to Follow

You are required to write code following the instructions provided above and test the correctness by running the designated test suite. Follow these steps exactly:

1. Update the code in #{buffer}{watch} using the @{insert_edit_into_file} tool
2. Then use the @{cmd_runner} tool to run the test suite with `<test_cmd>` (do this after you have updated the code)
3. Make sure you trigger both tools in the same response

We'll repeat this cycle until the tests pass. Ensure no deviations from these steps.]]
      end,
    },
  },
  --- Prompts to be continued ...
},
```

The first prompt in a workflow should set the ask of the LLM and provide clear instructions. In this case, we're giving the LLM access to the [@insert_edit_into_file](/usage/chat-buffer/agents.html#files) and [@cmd_runner](/usage/chat-buffer/agents.html#cmd-runner) tools to edit a buffer and run tests, respectively.

We're giving the LLM knowledge of the buffer with the `#buffer` variable and also telling CodeCompanion to watch it for any changes with the `{watch}` parameter. Prior to sending a response to the LLM, the plugin will share any changes to that buffer, keeping the LLM updated.

Now let's look at how we trigger the automated reflection prompts:

```lua
{
  {
    --- Prompts continued...
    {
      {
        name = "Repeat On Failure",
        role = constants.USER_ROLE,
        opts = { auto_submit = true },
        -- Scope this prompt to only run when the cmd_runner tool is active
        condition = function()
          return _G.codecompanion_current_tool == "cmd_runner"
        end,
        -- Repeat until the tests pass, as indicated by the testing flag
        repeat_until = function(chat)
          return chat.tools.flags.testing == true
        end,
        content = "The tests have failed. Can you edit the buffer and run the test suite again?",
      },
    },
  },
},
```

Now there's a little bit more to unpack in this prompt. Firstly, we're automatically submitting the prompt to the LLM to save the user some time and keypresses. Next, we're scoping the prompt to only be sent to the chat buffer if the currently active tool is the [@cmd_runner](/usage/chat-buffer/agents.html#cmd-runner).

We're also leveraging a function called `repeat_until`. This ensures that the prompt is always attached to the chat buffer until a condition is met. In this case, until the tests pass. In the [@cmd_runner](/usage/chat-buffer/agents.html#cmd-runner) tool, we ask the LLM to pass a flag if it detects a test suite is being run. The plugin picks up on that flag and puts the test outcome into the chat buffer class as a flag.

Finally, we're letting the LLM know that the tests failed, and asking it to fix.

## Useful Options

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

