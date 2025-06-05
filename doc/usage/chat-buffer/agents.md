# Using Agents and Tools

> [!IMPORTANT]
> Not all LLMs support function calling and the use of tools. Please see the [compatibility](#compatibility) section for more information.

<p align="center">
<img src="https://github.com/user-attachments/assets/f4a5d52a-0de5-422d-a054-f7e97bb76f62" />
</p>

As outlined by Andrew Ng in [Agentic Design Patterns Part 3, Tool Use](https://www.deeplearning.ai/the-batch/agentic-design-patterns-part-3-tool-use), LLMs can act as agents by leveraging external tools. Andrew notes some common examples such as web searching or code execution that have obvious benefits when using LLMs.

In the plugin, tools are simply context and actions that are shared with an LLM via a `system` prompt. The LLM can act as an agent by requesting tools via the chat buffer which in turn orchestrates their use within Neovim. Agents and tools can be added as a participant to the chat buffer by using the `@` key.

> [!IMPORTANT]
> The agentic use of some tools in the plugin results in you, the developer, acting as the human-in-the-loop and
> approving their use.

## How Tools Work

Tools make use of an LLM's [function calling](https://platform.openai.com/docs/guides/function-calling) ability. All tools in CodeCompanion follow OpenAI's function calling specification, [here](https://platform.openai.com/docs/guides/function-calling#defining-functions).

When a tool is added to the chat buffer, the LLM is instructured by the plugin to return a structured JSON schema which has been defined for each tool. The chat buffer parses the LLMs response and detects the tool use before triggering the _agent/init.lua_ file. The agent triggers off a series of events, which sees tool's added to a queue and sequentially worked with their putput being shared back to the LLM via the chat buffer. Depending on the tool, flags may be inserted on the chat buffer for later processing.

An outline of the architecture can be seen [here](/extending/tools#architecture).

## Community Tools

There is also a thriving ecosystem of user created tools:

- [VectorCode](https://github.com/Davidyz/VectorCode/tree/main) - A code repository indexing tool to supercharge your LLM experience
- [mcphub.nvim](https://github.com/ravitemer/mcphub.nvim) - A powerful Neovim plugin for managing MCP (Model Context Protocol) servers

The section of the discussion forums which is dedicated to user created tools can be found [here](https://github.com/olimorris/codecompanion.nvim/discussions/categories/tools).

## @cmd_runner

The _@cmd_runner_ tool enables an LLM to execute commands on your machine, subject to your authorization. For example:

```md
Can you use the @cmd_runner tool to run my test suite with `pytest`?
```

```md
Use the @cmd_runner tool to install any missing libraries in my project
```

Some commands do not write any data to [stdout](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)) which means the plugin can't pass the output of the execution to the LLM. When this occurs, the tool will instead share the exit code.

The LLM is specifically instructed to detect if you're running a test suite, and if so, to insert a flag in its request. This is then detected and the outcome of the test is stored in the corresponding flag on the chat buffer. This makes it ideal for [workflows](/extending/workflows) to hook into.

## @editor

The _@editor_ tool enables an LLM to modify the code in a Neovim buffer. If a buffer's content has been shared with the LLM then the tool can be used to add, edit or delete specific lines. Consider pinning or watching a buffer to avoid manually re-sending a buffer's content to the LLM:

```md
Use the @editor tool refactor the code in #buffer{watch}
```

```md
Can you apply the suggested changes to the buffer with the @editor tool?
```

## @files

> [!NOTE]
> All file operations require approval from the user before they're executed

The _@files_ tool leverages the [Plenary.Path](https://github.com/nvim-lua/plenary.nvim/blob/master/lua/plenary/path.lua) module to enable an LLM to perform various file operations on the user's disk:

- Creating a file
- Reading a file
- Editing a file
- Deleting a file

## @web_search

The _@web_search_ tool enables an LLM to search the web for a specific query. This can be useful to supplement an LLMs knowledge cut off date with more up to date information.

```md
Can you use the @web_search tool to tell me the latest version of Neovim?
```

## @next_edit_suggestion

Inspired by [Copilot Next Edit Suggestion](https://code.visualstudio.com/blogs/2025/02/12/next-edit-suggestions), the `@next_edit_suggestion` tool gives the LLM the ability to show you where the next edit is.
The LLM can only suggest edits in files that it knows, so this tool only works if you've sent some files in your project to the LLM. 
This can be done by `/file` or `/buffer` slash commands, the `#buffer` variable or other tools like `@vectorcode`.

The jump action can be customised by the `opts` table:
```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      tools = {
        ["next_edit_suggestion"] = {
          opts = {
            --- the default is to open in a new tab, and reuse existing tabs
            --- where possible
            ---@type string|fun(path: string):integer?
            jump_action = 'tabnew',
          },
        }
      }
    }
  }
})
```
The `jump_action` can be a VimScript command (as a string), or a lua function
that accepts the path to the file and optionally returns the [window ID](https://neovim.io/doc/user/windows.html#window-ID).

The window ID is needed if you want the LLM to point you to a specific line in
the file.

## @full_stack_dev

The plugin enables tools to be grouped together. The _@full_stack_dev_ agent is a combination of the _@cmd_runner_, _@editor_ and _@files_ tools:

```md
Let's use the @full_stack_dev tools to create a new app
```


## Approvals

Some tools, such as the _@cmd_runner_, require the user to approve any actions before they can be executed. If the tool requires this a `vim.fn.confirm` dialog will prompt you for a response.

## Useful Tips

### Combining Tools

Consider combining tools for complex tasks:

```md
@full_stack_dev I want to play Snake. Can you create the game for me in Python and install any packages you need. Let's save it to ~/Code/Snake. When you've finished writing it, can you open it so I can play?
```

### Automatic Tool Mode

The plugin allows you to run tools on autopilot. This automatically approves any tool use instead of prompting the user, disables any diffs, and automatically saves any buffers that the agent has edited. Simply set the global variable `vim.g.codecompanion_auto_tool_mode` to enable this or set it to `nil` to undo this. Alternatively, the keymap `gta` will toggle  the feature whist from the chat buffer.

## Compatibility

Below is the tool use status of various adapters and models in CodeCompanion:

| Adapter           | Model                      | Supported          | Notes                            |
|-------------------|----------------------------| :----------------: |----------------------------------|
| Anthropic         | claude-3-opus-20240229     | :white_check_mark: |                                  |
| Anthropic         | claude-3-5-haiku-20241022  | :white_check_mark: |                                  |
| Anthropic         | claude-3-5-sonnet-20241022 | :white_check_mark: |                                  |
| Anthropic         | claude-3-7-sonnet-20250219 | :white_check_mark: |                                  |
| Copilot           | gpt-4o                     | :white_check_mark: |                                  |
| Copilot           | gpt-4.1                    | :white_check_mark: |                                  |
| Copilot           | o1                         | :white_check_mark: |                                  |
| Copilot           | o3-mini                    | :white_check_mark: |                                  |
| Copilot           | o4-mini                    | :white_check_mark: |                                  |
| Copilot           | claude-3-5-sonnet          | :white_check_mark: |                                  |
| Copilot           | claude-3-7-sonnet          | :white_check_mark: |                                  |
| Copilot           | claude-3-7-sonnet-thought  | :x:                | Doesn't support function calling |
| Copilot           | gemini-2.0-flash-001       | :x:                |                                  |
| Copilot           | gemini-2.5-pro             | :white_check_mark: |                                  |
| DeepSeek          | deepseek-chat              | :white_check_mark: |                                  |
| DeepSeek          | deepseek-reasoner          | :x:                | Doesn't support function calling |
| Gemini            | Gemini-2.0-flash           | :white_check_mark: |                                  |
| Gemini            | Gemini-2.5-pro-exp-03-25   | :white_check_mark: |                                  |
| Gemini            | gemini-2.5-flash-preview   | :white_check_mark: |                                  |
| GitHub Models     | All                        | :x:                | Not supported yet                |
| Huggingface       | All                        | :x:                | Not supported yet                |
| Mistral           | All                        | :x:                | Not supported yet                |
| Novita            | All                        | :x:                | Not supported yet                |
| Ollama            | All                        | :x:                | Is currently [broken](https://github.com/ollama/ollama/issues/9632) |
| OpenAI Compatible | All                        | :exclamation:                | Dependent on the model and provider          |
| OpenAI            | gpt-3.5-turbo              | :white_check_mark: |                                  |
| OpenAI            | gpt-4.1                    | :white_check_mark: |                                  |
| OpenAI            | gpt-4                      | :white_check_mark: |                                  |
| OpenAI            | gpt-4o                     | :white_check_mark: |                                  |
| OpenAI            | gpt-4o-mini                | :white_check_mark: |                                  |
| OpenAI            | o1-2024-12-17              | :white_check_mark: |                                  |
| OpenAI            | o1-mini-2024-09-12         | :x:                | Doesn't support function calling |
| OpenAI            | o3-mini-2025-01-31         | :white_check_mark: |                                  |
| xAI               | All                        | :x:                | Not supported yet                |
