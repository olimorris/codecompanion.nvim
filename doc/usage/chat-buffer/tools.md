---
description: Learn how tools can aid your code, in CodeCompanion
---

# Using Tools

> [!IMPORTANT]
> Tools are not supported for ACP adapters as they have their own set.
> Not all LLMs support function calling and the use of tools. Please see the [compatibility](#compatibility) section for more information.

<p align="center">
<img src="https://github.com/user-attachments/assets/f4a5d52a-0de5-422d-a054-f7e97bb76f62" />
</p>

As outlined by Andrew Ng in [Agentic Design Patterns Part 3, Tool Use](https://www.deeplearning.ai/the-batch/agentic-design-patterns-part-3-tool-use), LLMs can act as agents by leveraging external tools. Andrew notes some common examples such as web searching or code execution that have obvious benefits when using LLMs.

In the plugin, tools are simply context and actions that are shared with an LLM. The LLM can act as an agent by executing tools via the chat buffer which in turn orchestrates their use within Neovim. Tools can be added as a participant to the chat buffer by using the `@` key.

> [!IMPORTANT]
> The use of some tools in the plugin results in you, the developer, acting as the human-in-the-loop and approving their use.

## How They Work

Tools make use of an LLM's [function calling](https://platform.openai.com/docs/guides/function-calling) ability. All tools in CodeCompanion follow OpenAI's function calling specification, [here](https://platform.openai.com/docs/guides/function-calling#defining-functions).

When a tool is added to the chat buffer, the LLM is instructured by the plugin to return a structured JSON schema which has been defined for each tool. The chat buffer parses the LLMs response and detects the tool use before triggering the _tools/init.lua_ file. The tool system triggers off a series of events, which sees tool's added to a queue and sequentially worked with their output being shared back to the LLM via the chat buffer. Depending on the tool, flags may be inserted on the chat buffer for later processing.

An outline of the architecture can be seen [here](/extending/tools#architecture).

## Built-in Tools

CodeCompanion comes with a number of built-in tools which you can leverage, as long as your adapter and model are [supported](#compatibility).

When calling a tool, CodeCompanion replaces the tool call in any prompt you send to the LLM with the value of a tool's `opts.tool_replacement_message` string. This is to ensure that you can call a tool efficiently whilst making the prompt readable to the LLM.

So calling a tool with:

```md
Use @{lorem_ipsum} to generate a random paragraph
```

will yield:

```md
Use the lorem_ipsum tool to generate a random paragraph
```

### cmd_runner

The _@cmd_runner_ tool enables an LLM to execute commands on your machine, subject to your authorization. For example:

```md
Can you use @{cmd_runner} to run my test suite with `pytest`?
```

```md
Use @{cmd_runner} to install any missing libraries in my project
```

Some commands do not write any data to [stdout](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)) which means the plugin can't pass the output of the execution to the LLM. When this occurs, the tool will instead share the exit code.

The LLM is specifically instructed to detect if you're running a test suite, and if so, to insert a flag in its request. This is then detected and the outcome of the test is stored in the corresponding flag on the chat buffer. This makes it ideal for [agentic workflows](/extending/agentic-workflows) to hook into.

**Options:**
- `require_approval_before` require approval before running a command? (Default: true)

### create_file

> [!NOTE]
> By default, this tool requires user approval before it can be executed

Create a file within the current working directory:

```md
Can you create some test fixtures using @{create_file}?
```

**Options:**
- `require_approval_before` require approval before creating a file? (Default: true)

### delete_file

> [!NOTE]
> By default, this tool requires user approval before it can be executed

Delete a file within the current working directory:

```md
Can you use @{delete_file} to delete the quotes.lua file?
```

**Options:**
- `require_approval_before` require approval before deleting a file? (Default: true)

### fetch_webpage

This tools enables an LLM to fetch the content from a specific webpage. It will return the text in a text format, depending on which adapter you've configured for the tool.

```md
Use @{fetch_webpage} to tell me what the latest version on neovim.io is
```

This tool supports 3 modes when fetching a website: 

- `text` (default): Returns `document.body.innerText`.
- `screenshot`: Returns the image URL of a screenshot of the first screen.
- `pageshot`: Returns the image URL of the full-page screenshot. 

The LLM choose which mode to use when they call the tool, and you can ask the LLM to use a specific mode in the chat.
Keep in mind that the `screenshot` and `pageshot` mode only make sense if you're using a multi-modal LLM, in which case you should also give it the `@{fetch_images}` tool so that it can fetch the screenshot/pageshot from the returned URL.


**Options:**
- `adapter` The adapter used to fetch, process and format the webpage's content (Default: `jina`)

### file_search

This tool enables an LLM to search for files in the current working directory by glob pattern. It will return a list of relative paths for any matching files.

```md
Use @{file_search} to list all the lua files in my project
```

**Options:**
- `max_results` limits the amount of results that can be sent to the LLM in the response (Default: 500)

### get_changed_files

This tool enables an LLM to get git diffs of any file changes in the current working directory. It will return a diff which can contain `staged`, `unstaged` and `merge-conflicts`.

```md
Use @{get_changed_files} see what's changed
```

**Options:**
- `max_lines` limits the amount of lines that can be sent to the LLM in the response (Default: 1000)

### grep_search

> [!IMPORTANT]
> This tool requires [ripgrep](https://github.com/BurntSushi/ripgrep) to be installed

This tool enables an LLM to search for text, within files, in the current working directory. For every match, the output (`{filename}:{line number} {relative filepath}`) will be shared with the LLM:

```md
Use @{grep_search} to find all occurrences of `buf_add_message`?
```

**Options:**
- `max_files` (number) limits the amount of files that can be sent to the LLM in the response (Default: 100)
- `respect_gitignore` (boolean) (Default: true)

### insert_edit_into_file

> [!NOTE]
> By default, when editing files, this tool requires user approval before it can be executed

<p>
  <video controls muted src="https://github.com/user-attachments/assets/990bbc99-7b12-4dca-8770-c24b9f3e7838"></video>
</p>

This tool can edit buffers and files for code changes from an LLM:

```md
Use @{insert_edit_into_file} to refactor the code in #buffer
```

```md
Can you apply the suggested changes to the buffer with @{insert_edit_into_file}?
```

**Options:**
- `patching_algorithm` (string|table|function) The algorithm to use to determine how to edit files and buffers
- `require_approval_before.buffer` (boolean) Require approval before editng a buffer? (Default: false)
- `require_approval_before.file` (boolean) Require approval before editng a file? (Default: true)
- `require_confirmation_after` (boolean) require confirmation after the execution and before moving on in the chat buffer? (Default: true)

### list_code_usages

> [!NOTE]
> This tool requires LSP to be configured and active for optimal results

This tool enables an LLM to find all usages of a symbol (function, class, method, variable, etc.) throughout your codebase. It leverages LSP for accurate results and falls back to grep for broader text searching.

The tool provides comprehensive information about symbols including:

- **References**: All places where the symbol is used
- **Definitions**: Where the symbol is defined
- **Implementations**: Concrete implementations of interfaces/abstract methods
- **Declarations**: Forward declarations
- **Type Definitions**: Type aliases and definitions
- **Documentation**: Hover documentation when available

```md
Use @{list_code_usages} to find all usages of the `create_file` function
```

```md
Can you use @{list_code_usages} to show me how the `Tools` class is implemented and used?
```

### memory

> [!IMPORTANT]
> For security, all memory operations are restricted to the `/memories` directory

The memory tool enables LLMs to store and retrieve information across conversations through a memory file directory (`/memories`).

If you're using the _Anthropic_ adapter, then this tool will act as its client implementation. Please refer to their [documentation](https://docs.claude.com/en/docs/agents-and-tools/tool-use/memory-tool) for more information.

The tool has the following commands that an LLM can use:

- **view** - Lists the contents in the `/memories` directory or displays file content with optional line ranges
- **create** - Creates a new file or overwrites an existing file with specified content
- **str_replace** - Replaces the first exact match of text in a file with new text
- **insert** - Inserts text at a specific line number in a file
- **delete** - Removes a file or recursively deletes a directory and all its contents
- **rename** - Moves or renames a file or directory to a new path

To use the tool:

```md
Use @{memory} to carry on our conversation about streamlining my dotfiles
```

### next_edit_suggestion

Inspired by [Copilot Next Edit Suggestion](https://code.visualstudio.com/blogs/2025/02/12/next-edit-suggestions), the tool gives the LLM the ability to show the user where the next edit is. The LLM can only suggest edits in files or buffers that have been shared with it as context.

**Options:**
- `jump_action` (string|function) Determines how a jump to the next edit is made (Default: `tabnew`)

### read_file

This tool can read the contents of a specific file in the current working directory. This can be useful for an LLM to gain wider context of files that haven't been shared with it.

### web_search

This tool enables an LLM to search the web for a specific query, enabling it to receive up to date information:

```md
Use @{web_search} to find the latest version of Neovim?
```

```md
Use @{web_search} to search neovim.io and explain how I can configure a new language server
```


Currently, the tool uses [tavily](https://www.tavily.com) and you'll need to ensure that an API key has been set accordingly, as per the [adapter](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/adapters/tavily.lua).
This tool also supports image results in the search that can be consumed by multi-modal LLMs.
To achieve that, you'd also need to give the `@{fetch_images}` tool to the LLM so that it can fetch the images from the URL.

### `fetch_images`

This tool allows the LLM to fetch images from URLs. 
Any URL that directly points to an image would work with this tool. 
While you could certainly copy-paste URLs to the chat buffer, it's probably more convenient to use this with the `@search_web` tool:

```md
Using the @{web_search} and @{fetch_images} tools, tell me what the logo of codecompanion.nvim look like.
```

**You should only use this tool with a multi-modal LLM.**

## Tool Groups

Tool Groups are a convenient way to combine multiple built-in tools together in the chat buffer. CodeCompanion comes with two built-in ones, `@{full_stack_dev}` and `@{files}`.

When you include a tool group in the chat, all tools within that group become available to the LLM. By default, all the tools in the group will be shown as a single `<group>name</group>` reference in the chat buffer. If you want to show all tools as context items in the chat buffer, set the `opts.collapse_tools` option to `false` on the group itself.

Groups may also have a `prompt` field which is used to replace their reference in a message in the chat buffer. This ensures that the LLM receives a useful message rather than the name of the tools themselves.

For example, the following prompt:

```md
@{full_stack_dev}. Can you create Snake for me, in Python?
```

Is replaced by:

```
I'm giving you access to the cmd_runner, create_file, file_search, get_changed_files, grep_search, insert_edit_into_file, list_code_usages, read_file tools to help you perform coding tasks. Can you create Snake for me, in Python?
```

This is because the `@{full_stack_dev}` group has the following prompt set in the config:

```lua
groups = {
  ["full_stack_dev"] = {
    -- ...
    prompt = "I'm giving you access to the ${tools} to help you perform coding tasks",
    -- ...
  }
},
```


### full_stack_dev

The `@{full_stack_dev}` is a collection of tools which have been curated to enable an LLM to create applications and understand and refactor code bases.

It contains the following tools:

- [cmd_runner](/usage/chat-buffer/tools#cmd-runner)
- [create_file](/usage/chat-buffer/tools#create-file)
- [file_search](/usage/chat-buffer/tools#file-search)
- [get_changed_files](/usage/chat-buffer/tools#get-changed-files)
- [grep_search](/usage/chat-buffer/tools#grep-search)
- [insert_edit_into_file](/usage/chat-buffer/tools#insert-edit-into-file)
- [list_code_usages](/usage/chat-buffer/tools#list-code-usages)
- [read_file](/usage/chat-buffer/tools#read-file)

You can use it with:

```md
@{full_stack_dev}. Can we create a todo list in Vue.js?
```

### files

The `@{files}` tool is a collection of tools that allows an LLM to carry out file operations in your current working directory. It contains the following files:

- [create_file](/usage/chat-buffer/tools#create-file)
- [file_search](/usage/chat-buffer/tools#file-search)
- [get_changed_files](/usage/chat-buffer/tools#get-changed-files)
- [grep_search](/usage/chat-buffer/tools#grep-search)
- [insert_edit_into_file](/usage/chat-buffer/tools#insert-edit-into-file)
- [read_file](/usage/chat-buffer/tools#read-file)

You can use it with:

```md
@{files}. Can you scaffold out the folder structure for a python package?
```

## Adapter Tools

> [!NOTE]
> Adapter tools are configured via the `available_tools` dictionary on the adapter itself

Prior to [v17.30.0](https://github.com/olimorris/codecompanion.nvim/releases/tag/v17.30.0), tool use in CodeCompanion was only possible with the built-in tools. However, that release unlocked _adapter_ tools. That is, tools that are owned by LLM providers such as [Anthropic](https://docs.claude.com/en/docs/agents-and-tools/tool-use/computer-use-tool) and [OpenAI](https://platform.openai.com/docs/guides/tools-web-search?api-mode=responses). This allows for remote tool execution of common tasks such as web searching and computer use.

From a UX perspective, there is no difference in using the built-in and adapter tools. However, please note that an adapter tool takes precedence over a built-in tool in the event of a name clash.

### Anthropic

In the `anthropic` adapter, the following tools are available:

- `code_execution` -  The code execution tool allows Claude to run Bash commands and manipulate files, including writing code, in a secure, sandboxed environment
- `memory` - Enables Claude to store and retrieve information across conversations through a memory file directory. Claude can create, read, update, and delete files that persist between sessions, allowing it to build knowledge over time without keeping everything in the context window
- `web_fetch` - The web fetch tool allows Claude to retrieve full content from specified web pages and PDF documents.
- `web_search` - The web search tool gives Claude direct access to real-time web content, allowing it to answer questions with up-to-date information beyond its knowledge cutoff

### OpenAI

In the `openai_responses` adapter, the following tools are available:

- `web_search` - Allow models to search the web for the latest information before generating a response.

## Security

CodeCompanion takes security very seriously, especially in a world of agentic code development. To that end, every effort is made to ensure that LLMs are only given the information that they need to execute a tool successfully. CodeCompanion will endeavour to make sure that the full disk path to your current working directory (cwd) in Neovim is never shared. The impact of this is that the LLM can only work within the cwd when executing tools but will minimize actions that are hard to [recover from](https://www.businessinsider.com/replit-ceo-apologizes-ai-coding-tool-delete-company-database-2025-7).

### Approvals

> [!NOTE]
> This applies to CodeCompanion's built-in tools only. ACP agents have their own tools and approval systems.

In order to give developers the confidence to use tools, CodeCompanion has implemented a comprehensive approval system for it's built-in tools.

CodeCompanion segregates tool approvals by chat buffer and by tool. This means that if you approve a tool in one chat buffer, it is _not_ approved for use anywhere else. Similarly, if you approve a tool once, you'll be prompted to approve it again next time it's executed.

When prompted, the user has four options available to them:

- **Allow always** - Always allow this tool/cmd to be executed without further prompts
- **Allow once** - Allow this tool/cmd to be executed this one time
- **Reject** - Reject the execution of this tool/cmd and provide a reason
- **Cancel** - Cancel this tool execution and all other pending tool executions

Certain tools with potentially destructive capabilities have an additional layer of protection. Instead of being approved at a tool level, these are approved at a command level. Taking the `cmd_runner` tool as an example. If you approve an agent to always run `make format`, if it tries to run `make test`, you'll be prompted to approve that command specifically.

Approvals can be reset for the given chat buffer by using the `gtx` keymap.

### YOLO mode

To bypass the approval system, you can use `gty` in the chat buffer to enable YOLO mode. This will automatically approve all tool executions without prompting the user. However, note that some tools such as `cmd_runner` and `delete_file` are excluded from this.

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
| Mistral           |                   | :white_check_mark: | Dependent on the model              |
| Novita            |                   | :white_check_mark: | Dependent on the model              |
| Ollama            | Tested with Qwen3 | :white_check_mark: | Dependent on the model              |
| OpenAI            |                   | :white_check_mark: | Dependent on the model              |
| xAI               | All               | :x:                | Not supported yet                   |


> [!IMPORTANT]
> When using Mistral, you will need to set `interactions.chat.tools.opts.auto_submit_errors` to `true`. See [#2278](https://github.com/olimorris/codecompanion.nvim/pull/2278) for more information.

