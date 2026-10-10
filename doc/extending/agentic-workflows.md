---
description: "Chain prompts with tool calls so an LLM can edit code, run your tests and keep fixing until they pass."
---

# Extending with Agentic Workflows

Some tasks take several turns, such as editing code, running the tests and fixing what fails, and prompting each turn by hand is slow. An _agentic workflow_ is a [workflow](/usage/workflows) that combines a series of prompts with [tools](/usage/chat-buffer/agents-tools), so the LLM can carry out the loop for you.

## How They Work

When you start a workflow from the [Action Palette](/usage/action-palette), the first group of prompts goes into a [chat buffer](/usage/chat-buffer/) and every later group is _subscribed_ to it. Each time the LLM finishes a response and the chat is ready for your input, CodeCompanion checks the subscriptions in order:

1. A prompt with a `condition` that returns `false` stays queued for a later turn
2. Otherwise the prompt is added to the chat buffer, and sent if `opts.auto_submit` is `true`
3. A prompt with `repeat_until` stays subscribed and is added again on every turn until `repeat_until` returns `true`. Any other prompt is removed once it's been added

Stopping or cancelling a request, or closing the chat buffer, stops any further prompts from being sent automatically.

## Prompt Fields

Each prompt in a workflow can use:

| Field | Description |
| --- | --- |
| `role` | `"user"` or `"system"` |
| `content` | A string, or a function that receives the buffer context and returns one |
| `name` | A label for the prompt, shown in the logs |
| `opts.auto_submit` | Send the prompt as soon as it's added |
| `opts.adapter` | Switch to this adapter and model, as `{ name = "copilot", model = "gpt-4.1" }`, when the prompt is added |
| `condition` | A function that receives the chat buffer and returns whether the prompt can be added this turn |
| `repeat_until` | A function that receives the chat buffer and returns `true` once the prompt should stop repeating |

## Edit and Test

The `Edit<->Test` workflow originally came with the plugin. It asks the LLM to edit a buffer and run the test suite, then sends the failures back until the tests pass:

```lua
require("codecompanion").setup({
  prompt_library = {
    ["Edit<->Test workflow"] = {
      interaction = "chat",
      description = "Use a workflow to repeatedly edit then test code",
      opts = {
        approval_mode = "auto",
        is_workflow = true,
      },
      prompts = {
        {
          {
            name = "Setup Test",
            role = "user",
            opts = { auto_submit = false },
            content = function()
              return [[### Instructions

Your instructions here

### Steps to Follow

You are required to write code following the instructions provided above and test the correctness by running the designated test suite. Follow these steps exactly:

1. Update the code in #{buffer} using the @{edit_file} tool
2. Then use the @{run_command} tool to run the test suite with `<test_cmd>` (do this after you have updated the code)
3. Make sure you trigger both tools in the same response

We'll repeat this cycle until the tests pass. Ensure no deviations from these steps.]]
            end,
          },
        },
        {
          {
            name = "Repeat On Failure",
            role = "user",
            opts = { auto_submit = true },
            condition = function(chat)
              return chat.tool_registry.flags.testing ~= nil
            end,
            repeat_until = function(chat)
              return chat.tool_registry.flags.testing == true
            end,
            content = "The tests have failed. Can you edit the buffer and run the test suite again?",
          },
        },
      },
    },
  },
})
```

`approval_mode = "auto"` starts the chat in [Auto mode](/usage/chat-buffer/agents-tools#approval-modes), so the edits go ahead without asking.

### Setting the Task

The first prompt sets the task and isn't sent automatically, so you can replace `Your instructions here` and `<test_cmd>` before sending it. It gives the LLM the [edit_file](/usage/chat-buffer/agents-tools#edit-file) and [run_command](/usage/chat-buffer/agents-tools#run-command) tools, and shares the buffer with `#{buffer}`. The buffer is [synced](/usage/chat-buffer/editor-context#syncing), so the LLM sees each change it makes on the next turn.

### Repeating on Failure

The second prompt drives the loop. The `run_command` tool asks the LLM to flag any command that runs a test suite. CodeCompanion then records whether the tests passed as `chat.tool_registry.flags.testing`:

- **`condition`** - Waits until the LLM has run the tests, as the flag is `nil` before then
- **`repeat_until`** - Sends the prompt again after every failing run, and stops once the tests pass
- **`opts.auto_submit`** - Sends the prompt without waiting for you
