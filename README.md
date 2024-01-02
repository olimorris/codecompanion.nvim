<!-- panvimdoc-ignore-start -->

<p align="center">
<img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/f18e654c-27f6-4712-9913-00ed2f3f4bd9" alt="CodeCompanion.nvim" />
</p>

<h1 align="center">CodeCompanion.nvim</h1>

<!-- <p align="center"> -->
<!-- <a href="https://github.com/olimorris/codecompanion.nvim/stargazers"><img src="https://img.shields.io/github/stars/olimorris/codecompanion.nvim?color=c678dd&logoColor=e06c75&style=for-the-badge"></a> -->
<!-- <a href="https://github.com/olimorris/codecompanion.nvim/issues"><img src="https://img.shields.io/github/issues/olimorris/codecompanion.nvim?color=%23d19a66&style=for-the-badge"></a> -->
<!-- <a href="https://github.com/olimorris/codecompanion.nvim/blob/main/LICENSE"><img src="https://img.shields.io/github/license/olimorris/codecompanion.nvim?style=for-the-badge"></a> -->
<!-- <a href="https://github.com/olimorris/codecompanion.nvim/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/olimorris/codecompanion.nvim/ci.yml?branch=main&label=tests&style=for-the-badge"></a> -->
<!-- </p> -->

<p align="center">
A wrapper around the OpenAI <a href="https://platform.openai.com/docs/guides/text-generation/chat-completions-api">Chat Completions API</a>. Use it to chat, write and advise you on your code from within Neovim.<br>
</p>

<!-- panvimdoc-ignore-end -->

## Features

- Chat with OpenAI's API via a Neovim buffer
- Define custom actions for Neovim which hook into OpenAI
- UI selector to pick which action to run
- Asynchronous and non-blocking

## Actions

Actions take prompts as input and send them to the Chat Completions API. The prompts can be composed of inputs from the user, code which has been selected from within Neovim or additional context which has been computed at runtime.

### Strategies

Actions are principally made up of `strategies`, which are the various ways that the plugin will interact with your code:

- `chat` - A strategy for talking directly to the API in a separate buffer
- `advisor` - A strategy whereby the API will advise you about your code
- `author` - A strategy whereby the API will write code for you
- `workspace` - A strategy whereby multiple files can be sent to the API alongside a prompt

### Breaking down the default actions

#### Code Companion

Let's take a look at one of the default `author` actions in the plugin, the `Code Companion`:

<details>
  <summary>Click to see the configuration</summary>

```lua
{
    name = "Code Companion",
    strategy = "author",
    description = "Prompt the Completions API to write/refactor code",
    opts = {
        model = "gpt-4-1106-preview",
        modes = { "n", "v" },
        user_input = true,
        send_visual_selection = true,
    },
    prompts = {
        [1] = {
            role = "system",
            content = [[I want you to act as a senior %s developer. I will ask you specific questions and I want you to return raw code only (no codeblocks and no explanations).
            If you can't respond with code, just say "Error - I don't know".]],
            variables = {
                "filetype",
            },
        },
    },
},
```

</details>

Breaking it down:

- `strategy` - The author strategy has write access to the current buffer
- `opts.model` - The OpenAI model to interact with
- `opts.modes` - The Vim modes for which this action can work in
- `opts.user_input` - Do we want to prompt the user for their own input?
- `opts.send_visual_selection` - Do we want to automatically send any visual selection to the API?

The `prompts` structure follows the [Chat Completions API](https://platform.openai.com/docs/guides/text-generation/chat-completions-api) format of `role` and `content`. The `system` prompt informs the API of how it should behave when answering any questions. In essence it sets the tone for the response. The plugin allows for you to subsitute variables into the prompt with `%s` and the `variables` table. In this case we're substituting the filetype of the buffer into the prompt. More on this later.

#### LSP Assistant

Let's look at a more advanced action which utilises the `advisor` strategy, the `LSP Assistant`:

<details>
  <summary>Click to see the configuration</summary>

```lua
{
    name = "LSP Assistant",
    strategy = "advisor",
    description = "Get help from the Completions API to fix LSP diagnostics",
    opts = {
        model = "gpt-4-1106-preview",
        modes = { "v" },
        user_input = false,
        send_visual_selection = false,
    },
    prompts = {
        [1] = {
            role = "system",
            content = [[You are an expert coder and helpful assistant who can help debug code diagnostics, such as warning and error messages.
            When appropriate, give solutions with code snippets as fenced codeblocks with a language identifier to enable syntax highlighting.
            If you can't respond with an answer, just say "Error - I don't know".]],
        },
        [2] = {
            role = "user",
            content = function(context)
                local diagnostics = require("openai.helpers.lsp").get_diagnostics(
                    context.start_line,
                    context.end_line,
                    context.bufnr
                )

                local concatenated_diagnostics = ""
                for i, diagnostic in ipairs(diagnostics) do
                    concatenated_diagnostics = concatenated_diagnostics
                    .. i
                    .. ". Issue "
                    .. i
                    .. "\n\t- Location: Line "
                    .. diagnostic.line_number
                    .. "\n\t- Severity: "
                    .. diagnostic.severity
                    .. "\n\t- Message: "
                    .. diagnostic.message
                    .. "\n"
                end

                return "The programming language is "
                    .. context.filetype
                    .. ".\nThis is a list of the diagnostic messages:\n"
                    .. concatenated_diagnostics
            end,
        },
        [3] = {
            role = "user",
            content = function(context)
                return "This is the code, for context:\n"
                    .. require("openai.helpers.code").get_code(context.start_line, context.end_line)
            end,
        },
    }
},
```

</details>

Breaking it down:

- `strategy` - The advisor strategy has read access to the current buffer
- `opts.modes` - This time we're telling the action to only work in Visual mode
- `opts.user_input` - We're also telling the action to not prompt the user for input
- `opts.send_visual_selection` - We're also disabling the default behaviour of sending a visual selection to the API

In this example, the prompts structure is more complicated. It is now a function which returns a string and we're utilising the `context` table as a parameter to do some more complicated prompt generation. The `context` table is generated from the buffer where the action was initiated. It contains the following items:

- `bufnr` `(int)` - The buffer number for the buffer to carry out the action in
- `mode` `(str)` - The Vim mode that called the action
- `is_visual` `(bool)` - Did the user call the action in Visual mode?
- `is_normal` `(bool)` - Did the user call the action in Normal mode?
- `buftype` `(str)` - The buffer type
- `filetype` `(str)` - The buffer's filetype
- `cursor_pos` `(tbl)` - The position of the cursor when the action was called
- `lines` `(tbl)` - The selected lines in the buffer, if in visual mode
- `start_line` `(int)` - The line number the selection starts at
- `end_line` `(int)` - The line number the selection ends at
- `start_col` `(int)` - The column the selection starts at
- `end_col` `(int)` - The column the selection ends at

With this level of context, it allows us to do some advanced prompting, like extracting the LSP's diagnostic messages for the selected lines of code. Finally, for the last prompt, we fetch the selected code and send that as context to the API.

