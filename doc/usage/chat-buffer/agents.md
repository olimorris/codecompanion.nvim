# Using Agents and Tools

> [!IMPORTANT]
> As of `v17.5.0`, tools must be wrapped in curly braces, such as `@{grep_search}` or `@{files}`

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

When a tool is added to the chat buffer, the LLM is instructured by the plugin to return a structured JSON schema which has been defined for each tool. The chat buffer parses the LLMs response and detects the tool use before triggering the _agent/init.lua_ file. The agent triggers off a series of events, which sees tool's added to a queue and sequentially worked with their output being shared back to the LLM via the chat buffer. Depending on the tool, flags may be inserted on the chat buffer for later processing.

An outline of the architecture can be seen [here](/extending/tools#architecture).

## Community Tools

There is also a thriving ecosystem of user created tools:

- [VectorCode](https://github.com/Davidyz/VectorCode/tree/main) - A code repository indexing tool to supercharge your LLM experience
- [mcphub.nvim](https://github.com/ravitemer/mcphub.nvim) - A powerful Neovim plugin for managing MCP (Model Context Protocol) servers

The section of the discussion forums which is dedicated to user created tools can be found [here](https://github.com/olimorris/codecompanion.nvim/discussions/categories/tools).

## cmd_runner

The _@cmd_runner_ tool enables an LLM to execute commands on your machine, subject to your authorization. For example:

```md
Can you use the @{cmd_runner} tool to run my test suite with `pytest`?
```

```md
Use the @{cmd_runner} tool to install any missing libraries in my project
```

Some commands do not write any data to [stdout](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)) which means the plugin can't pass the output of the execution to the LLM. When this occurs, the tool will instead share the exit code.

The LLM is specifically instructed to detect if you're running a test suite, and if so, to insert a flag in its request. This is then detected and the outcome of the test is stored in the corresponding flag on the chat buffer. This makes it ideal for [workflows](/extending/workflows) to hook into.

**Options:**
- `requires_approval` require approval before running a command? (Default: true)

## create_file

> [!NOTE]
> By default, this tool requires user approval before it can be executed

Create a file within the current working directory:

```md
Can you create some test fixtures using the @{create_file} tool?
```

**Options:**
- `requires_approval` require approval before creating a file? (Default: true)

## file_search

This tool enables an LLM to search for files in the current working directory by glob pattern. It will return a list of relative paths for any matching files.

```md
Use the @{file_search} tool to list all the lua files in my project
```

**Options:**
- `max_results` limits the amount of results that can be sent to the LLM in the response (Default: 500)

## get_changed_files

This tool enables an LLM to get git diffs of any file changes in the current working directory. It will return a diff which can contain `staged`, `unstaged` and `merge-conflicts`.

```md
Use the @{get_changed_files} tool see what's changed
```

**Options:**
- `max_lines` limits the amount of lines that can be sent to the LLM in the response (Default: 1000)

## grep_search

> [!IMPORTANT]
> This tool requires [ripgrep](https://github.com/BurntSushi/ripgrep) to be installed

This tool enables an LLM to search for text, within files, in the current working directory. For every match, the output (`{filename}:{line number} {relative filepath}`) will be shared with the LLM:

```md
Use the @{grep_search} tool to find all occurrences of `buf_add_message`?
```

**Options:**
- `max_files` (number) limits the amount of files that can be sent to the LLM in the response (Default: 100)
- `respect_gitignore` (boolean) (Default: true)

## insert_edit_into_file

> [!NOTE]
> By default, when editing files, this tool requires user approval before it can be executed

<p>
  <video controls muted src="https://github.com/user-attachments/assets/990bbc99-7b12-4dca-8770-c24b9f3e7838"></video>
</p>

This tool can edit buffers and files for code changes from an LLM:

```md
Use the @{insert_edit_into_file} tool to refactor the code in #buffer
```

```md
Can you apply the suggested changes to the buffer with the @{insert_edit_into_file} tool?
```

**Options:**
- `patching_algorithm` (string|table|function) The algorithm to use to determine how to edit files and buffers
- `requires_approval.buffer` (boolean) Require approval before editng a buffer? (Default: false)
- `requires_approval.file` (boolean) Require approval before editng a file? (Default: true)
- `user_confirmation` (boolean) require confirmation from the user before moving on in the chat buffer? (Default: true)

## next_edit_suggestion

Inspired by [Copilot Next Edit Suggestion](https://code.visualstudio.com/blogs/2025/02/12/next-edit-suggestions), the tool gives the LLM the ability to show the user where the next edit is. The LLM can only suggest edits in files or buffers that have been shared with it as context.

**Options:**
- `jump_action` (string|function) Determines how a jump to the next edit is made (Default: `tabnew`)

## read_file

This tool can read the contents of a specific file in the current working directory. This can be useful for an LLM to gain wider context of files that haven't been shared with it.

## web_search

The _@web_search_ tool enables an LLM to search the web for a specific query. This can be useful to supplement an LLMs knowledge cut off date with more up to date information.

```md
Can you use the @{web_search} tool to tell me the latest version of Neovim?
```

Currently, the tool uses [tavily](https://www.tavily.com) and you'll need to ensure that an API key has been set accordingly, as per the [adapter](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/adapters/tavily.lua).

You can also ask it to search under a specific domain:
```
Using the @web_search tool to search from `https://neovim.io` and explain how I can configure a new language server.
```

## Tool Groups

CodeCompanion comes with two built-in tool groups:

- `full_stack_dev` - Containing all of the tools
- `files` - Containing `create_file`, `file_search`, `get_changed_files`, `grep_search`, `insert_edit_into_file` and `read_file` tools

When you include a tool group in your chat (e.g., `@{files}`), all tools within that group become available to the LLM. By default, all the tools in the group will be shown as a single `<group>name</group>` reference in the chat buffer.

If you want to show all tools as references in the chat buffer, set the `opts.collapse_tools` option to `false` on the group itself.

## Approvals

Some tools, such as the _@cmd_runner_, require the user to approve any actions before they can be executed. If the tool requires this a `vim.fn.confirm` dialog will prompt you for a response.

## Useful Tips

### Combining Tools

Consider combining tools for complex tasks:

```md
@{full_stack_dev} I want to play Snake. Can you create the game for me in Python and install any packages you need. Let's save it to ~/Code/Snake. When you've finished writing it, can you open it so I can play?
```

### Automatic Tool Mode

The plugin allows you to run tools on autopilot. This automatically approves any tool use instead of prompting the user, disables any diffs, submits errors and success messages and automatically saves any buffers that the agent has edited. Simply set the global variable `vim.g.codecompanion_auto_tool_mode` to enable this or set it to `nil` to undo this. Alternatively, the keymap `gta` will toggle  the feature whist from the chat buffer.

## Compatibility

Below is the tool use status of various adapters and models in CodeCompanion:

| Adapter           | Model             | Supported          | Notes                               |
|-------------------|-------------------| :----------------: |-------------------------------------|
| Anthropic         |                   | :white_check_mark: | Dependent on the model              |
| Azure OpenAI      |                   | :white_check_mark: | Dependent on the model              |
| Copilot           |                   | :white_check_mark: | Dependent on the model              |
| DeepSeek          |                   | :white_check_mark: | Dependent on the model              |
| Gemini            |                   | :white_check_mark: | Dependent on the model              |
| GitHub Models     | All               | :x:                | Not supported yet                   |
| Huggingface       | All               | :x:                | Not supported yet                   |
| Mistral           | All               | :x:                | Not supported yet                   |
| Novita            | All               | :x:                | Not supported yet                   |
| Ollama            | Tested with Qwen3 | :white_check_mark: | Dependent on the model              |
| OpenAI Compatible |                   | :exclamation:      | Dependent on the model and provider |
| OpenAI            |                   | :white_check_mark: | Dependent on the model              |
| xAI               | All               | :x:                | Not supported yet                   |
