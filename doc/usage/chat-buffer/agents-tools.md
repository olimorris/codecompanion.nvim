---
description: "Let an LLM edit files, run commands and search the web from the chat buffer, with tool groups, approvals and approval modes."
---

# Using Agents and Tools

> [!IMPORTANT]
> The built-in tools are for HTTP adapters only, and not every LLM supports tool use. See [compatibility](#compatibility)

<p align="center">
<img src="https://github.com/user-attachments/assets/f2c17a2b-780a-4914-a983-5b0610d96427" alt="Using an agent in the chat buffer" />
</p>

An LLM acts as an agent when it can use tools, such as searching the web or running code ([Agentic Design Patterns Part 3, Tool Use](https://www.deeplearning.ai/the-batch/agentic-design-patterns-part-3-tool-use)). In CodeCompanion, a tool is context and an action shared with the LLM, which the chat buffer runs inside Neovim on the LLM's behalf. Add a tool to the chat buffer by typing `@`.

> [!IMPORTANT]
> Some tools need your approval before they run, making you the human in the loop

## How They Work

Tools use an LLM's [function calling](https://platform.openai.com/docs/guides/function-calling) ability. Every tool in CodeCompanion follows [OpenAI's specification for defining functions](https://platform.openai.com/docs/guides/function-calling#defining-functions).

For HTTP adapters, CodeCompanion is the _harness_: the system prompt, tools, approvals and [context management](/architecture#how-context-is-managed) that turn an LLM into an agent. ACP adapters such as Claude Code and Codex bring their own harness, which is why the built-in tools are for HTTP adapters only.

The harness runs the _agent loop_:

1. You submit a prompt
2. The LLM responds, optionally asking to run one or more tools
3. CodeCompanion runs each tool in turn, asking for your [approval](#approvals) where needed
4. The tools' output is sent back to the LLM and the loop returns to step 2

The loop ends when the LLM responds without asking for a tool, or when you stop the request or cancel a tool. Rejecting a tool doesn't end the loop. The LLM is told you rejected it, along with your reason, and carries on.

The [tool system architecture](/extending/tools#architecture) is outlined in the extending section.

## Tool Groups

A _tool group_ makes several tools available to the LLM with a single `@{group_name}` reference. CodeCompanion comes with two: `@{agent}` and `@{files}`.

By default, a group shows as a single `<group>name</group>` context item in the chat buffer. To list each of its tools as a context item instead, set `opts.collapse_tools = false` on the group.

A group's `prompt` replaces its reference in your message, so the LLM receives a sentence rather than the group's name. `${tools}` in the prompt expands to the group's tools.

### agent

The `@{agent}` group is CodeCompanion's agent mode. It has its own system prompt, which replaces the default chat and tool system prompts, and contains:

- [ask_questions](#ask-questions)
- [create_file](#create-file)
- [delete_file](#delete-file)
- [edit_file](#edit-file)
- [file_search](#file-search)
- [get_changed_files](#get-changed-files)
- [get_diagnostics](#get-diagnostics)
- [grep_search](#grep-search)
- [read_file](#read-file)
- [run_command](#run-command)

To use it:

```md
@{agent} Can we create a todo list app in Vue.js?
```

### files

The `@{files}` group carries out file operations in the current working directory. It contains:

- [create_file](#create-file)
- [delete_file](#delete-file)
- [edit_file](#edit-file)
- [file_search](#file-search)
- [get_changed_files](#get-changed-files)
- [grep_search](#grep-search)
- [read_file](#read-file)

To use it:

```md
@{files} Can you scaffold out the folder structure for a python package?
```

### Custom Agents

A group becomes an agent when it has its own `system_prompt`. With `ignore_system_prompt` and `ignore_tool_system_prompt`, it replaces the default system prompts entirely. This is how `@{agent}` works.

A `system_prompt` function receives the group's config and a [context object](/configuration/system-prompt) with `language`, `cwd`, `date`, `nvim_version`, `os` and more:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        groups = {
          ["my_agent"] = {
            description = "My custom agent",
            system_prompt = function(group, ctx)
              return string.format("You are a coding agent. The date is %s. The user is on %s.", ctx.date, ctx.os)
            end,
            tools = { "read_file", "edit_file", "run_command" },
            opts = {
              collapse_tools = true,
              ignore_system_prompt = true,
              ignore_tool_system_prompt = true,
            },
          },
        },
      },
    },
  },
})
```

## Built-in Tools

The built-in tools work with any adapter and model that [supports tool use](#compatibility):

| Tool | Description |
| --- | --- |
| [ask_questions](#ask-questions) | Ask you clarifying questions before acting |
| [create_file](#create-file) | Create a file |
| [delete_file](#delete-file) | Delete a file in the current working directory |
| [edit_file](#edit-file) | Edit a buffer or file by replacing exact text |
| [fetch_webpage](#fetch-webpage) | Fetch the content of a webpage |
| [file_search](#file-search) | Find files by glob pattern |
| [get_changed_files](#get-changed-files) | Get git diffs of the current changes |
| [get_diagnostics](#get-diagnostics) | Get LSP diagnostics for a file |
| [grep_search](#grep-search) | Search for text in files |
| [memory](#memory) | Store and retrieve information across conversations |
| [read_file](#read-file) | Read all or part of a file |
| [run_command](#run-command) | Run shell commands |
| [search_help](#search-help) | Search the CodeCompanion docs |
| [web_search](#web-search) | Search the web |

When you send a prompt, each tool reference is replaced with `interactions.chat.tools.opts.tool_replacement_message`, which defaults to `"the ${tool} tool"`. So this:

```md
Use @{grep_search} to find where the adapter is resolved
```

reaches the LLM as:

```md
Use the grep_search tool to find where the adapter is resolved
```

### ask_questions

> [!NOTE]
> This tool is hidden from the completion menu and comes with the `@{agent}` group

The LLM asks you up to four clarifying questions before acting. It uses this when requirements are ambiguous, when it needs to choose between approaches or when it wants to check an assumption:

```md
@{agent} Can you refactor the authentication module?
```

### create_file

> [!NOTE]
> By default, you see a preview of the file's contents and confirm it before the file is created

```md
Can you create some test fixtures using @{create_file}?
```

| Option | Default | Description |
| --- | --- | --- |
| `require_approval_before` | `false` | Require approval before showing the preview |
| `require_confirmation_after` | `true` | Show a preview of the contents and require confirmation before creating the file |

### delete_file

> [!NOTE]
> By default, this tool requires your approval before it runs

```md
Can you use @{delete_file} to delete the quotes.lua file?
```

| Option | Default | Description |
| --- | --- | --- |
| `judge` | `false` | Let the [LLM judge](/configuration/tools#llm-judge) decide in Auto mode |
| `protect` | `true` | Always ask before deleting a file in Auto mode |
| `require_approval_before` | `true` | Require approval before deleting a file |

### edit_file

> [!NOTE]
> By default, you confirm each edit in a diff before it's written

<p>
  <video controls muted title="edit_file tool demo" src="https://github.com/user-attachments/assets/990bbc99-7b12-4dca-8770-c24b9f3e7838"></video>
</p>

The LLM edits buffers and files by replacing an exact piece of text with new text:

```md
Use @{edit_file} to refactor the code in #buffer
```

The text being replaced must match the file exactly, including indentation. If it can't be found, or it appears more than once, the edit fails and the LLM is told why so it can try again. A file that's open in Neovim is edited in its buffer and saved, and any other file keeps its line endings.

| Option | Default | Description |
| --- | --- | --- |
| `require_approval_before.buffer` | `false` | Require approval before editing a buffer |
| `require_approval_before.file` | `false` | Require approval before editing a file |
| `require_confirmation_after` | `true` | Require confirmation of the diff before the edit is written |
| `file_size_limit_mb` | `2` | Files larger than this aren't edited |

### fetch_webpage

The LLM fetches the content of a webpage, converted to text by the tool's adapter:

```md
Use @{fetch_webpage} to tell me what the latest version on neovim.io is
```

| Option | Default | Description |
| --- | --- | --- |
| `adapter` | `"markitdown"` | The adapter that fetches and converts the page. Can be `"markitdown"` or `"jina"` |

### file_search

The LLM finds files in the current working directory by glob pattern, and receives the matching paths:

```md
Use @{file_search} to list all the lua files in my project
```

| Option | Default | Description |
| --- | --- | --- |
| `max_results` | `500` | Maximum number of paths sent to the LLM |

### get_changed_files

The LLM gets git diffs of the changes in the current working directory, covering staged, unstaged and merge conflicted files:

```md
Use @{get_changed_files} to see what's changed
```

| Option | Default | Description |
| --- | --- | --- |
| `max_lines` | `1000` | Maximum number of diff lines sent to the LLM |

### get_diagnostics

> [!WARNING]
> This tool relies on language servers, so it may be unreliable for some filetypes

The LLM gets the LSP diagnostics for a file (errors, warnings, information and hints) along with the lines they refer to:

```md
Use @{get_diagnostics} to check for any issues in the current file
```

The LLM can pass a minimum `severity` of `ERROR`, `WARNING`, `INFORMATION` or `HINT`. It defaults to `HINT`, which includes everything.

### grep_search

> [!IMPORTANT]
> This tool requires [ripgrep](https://github.com/BurntSushi/ripgrep) and is unavailable without it

The LLM searches for text in files in the current working directory, and receives the path and line number of each match:

```md
Use @{grep_search} to find all occurrences of `buf_add_message`
```

| Option | Default | Description |
| --- | --- | --- |
| `max_results` | `100` | Maximum number of matches sent to the LLM |
| `require_approval_before` | `true` | Require approval before searching |
| `respect_gitignore` | `true` | Skip files ignored by git |

### memory

> [!IMPORTANT]
> Every memory operation is restricted to the `/memories` directory and any whitelisted paths

The LLM stores and retrieves information across conversations in a memory directory, `<cwd>/memories`. With the Anthropic adapter, this tool is the client side of Anthropic's [memory tool](https://docs.claude.com/en/docs/agents-and-tools/tool-use/memory-tool).

```md
Use @{memory} to carry on our conversation about streamlining my dotfiles
```

The LLM can use these commands:

| Command | Description |
| --- | --- |
| `view` | List a directory, two levels deep, or show a file with an optional line range |
| `create` | Create a file, or overwrite an existing one |
| `str_replace` | Replace text in a file, which must match exactly once |
| `insert` | Insert text at a line number |
| `delete` | Delete a file, or a directory and everything in it |
| `rename` | Move or rename a file or directory |

By default, the tool requires your approval before it runs (`require_approval_before = true`).

**Whitelisted Paths**

To give the LLM access to paths outside `<cwd>/memories`, map each one to a virtual prefix:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["memory"] = {
          opts = {
            whitelist = {
              { path = "~/.dotfiles", as = "/dotfiles" },
              { path = "/shared/notes", as = "/notes" },
            },
          },
        },
      },
    },
  },
})
```

The LLM then uses `/dotfiles/.zshrc` or `/notes/todo.md` just as it uses `/memories/file.txt`. A `~` is expanded, and directory traversal protection applies to every whitelisted path.

A single file can be mounted too, such as a personal profile the LLM learns from and updates over time:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["memory"] = {
          opts = {
            whitelist = {
              { path = "~/.dotfiles/PERSONAL.md", as = "/personal" },
            },
          },
        },
      },
    },
  },
})
```

### read_file

The LLM reads all or part of a file, using an absolute path or one relative to the current working directory. This gives it context from files you haven't shared:

```md
Use @{read_file} to read the README and summarise the project
```

| Option | Default | Description |
| --- | --- | --- |
| `require_approval_before` | `true` | Require approval before reading a file |

### run_command

The LLM runs shell commands on your machine:

```md
Can you use @{run_command} to run my test suite with `pytest`?
```

If a command succeeds without writing to [stdout](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)), the LLM is told there was no output. If it fails, the LLM receives its stderr and stdout.

The LLM is instructed to flag a command that runs a test suite. CodeCompanion then records whether the tests passed as a flag on the chat buffer, which [agentic workflows](/extending/agentic-workflows) can hook into.

| Option | Default | Description |
| --- | --- | --- |
| `judge` | `false` | Let the [LLM judge](/configuration/tools#llm-judge) decide in Auto mode |
| `require_approval_before` | `true` | Require approval before running a command |
| `safe_commands` | `{ "git status", "ls", "pwd" }` | Commands that run without asking in Auto mode |
| `timeout` | `300000` | Milliseconds before a command is terminated |

### search_help

The LLM searches the CodeCompanion docs, grounding its answers in the plugin's documentation rather than its own, possibly out of date, knowledge:

```md
Use @{search_help} to find out how I can do a code review in CodeCompanion
```

### web_search

The LLM searches the web, so it can answer with up to date information:

```md
Use @{web_search} to search neovim.io and explain how I can configure a new language server
```

By default, the tool uses DuckDuckGo, which needs no API key. Other search providers can be [configured](/configuration/tools#web-search).

## Adapter Tools

> [!NOTE]
> Adapter tools are configured in the `available_tools` table on the adapter

_Adapter tools_ are owned by LLM providers and run remotely, covering tasks such as web search and code execution. They were added in [v17.30.0](https://github.com/olimorris/codecompanion.nvim/releases/tag/v17.30.0). You use them in the same way as the built-in tools, and **an adapter tool takes precedence over a built-in tool of the same name**.

| Adapter | Tool | Description |
| --- | --- | --- |
| `anthropic` | `code_execution` | Run Bash commands and manipulate files in a sandbox |
| `anthropic` | `memory` | Store and retrieve information across conversations, using the [memory](#memory) tool as its client |
| `anthropic` | `web_fetch` | Retrieve the full content of webpages and PDF documents |
| `anthropic` | `web_search` | Search the web for up to date information |
| `gemini` | `web_search` | Search the web with Google Search |
| `openai` | `web_search` | Search the web for up to date information |
| `openrouter` | `fetch_webpage` | Fetch the content of a URL, with any model |
| `openrouter` | `web_search` | Search the web, with any model |

## MCP

The tools from your [configured](/configuration/mcp) MCP servers are available in the chat buffer once a server has started. Type `@` to find them in the completion menu, prefixed with `mcp:`.

## Security

Tools are designed to keep the LLM from making changes that are hard to [recover from](https://www.businessinsider.com/replit-ceo-apologizes-ai-coding-tool-delete-company-database-2025-7). `delete_file` refuses any path outside the current working directory, and `memory` is restricted to its own directory and any whitelisted paths.

### Approvals

> [!NOTE]
> This applies to CodeCompanion's built-in tools only. ACP agents have their own tools and approval systems

Approvals are kept per chat buffer and per tool. Approving a tool in one chat buffer doesn't approve it anywhere else, and approving it once means you're asked again next time.

When asked, you choose from:

| Keymap | Choice | Description |
| --- | --- | --- |
| `g1` | Always accept | Run this tool without asking again in this chat buffer |
| `g2` | Accept | Run this tool this one time |
| `g3` | Reject | Don't run the tool, and give the LLM a reason |
| `g4` | Cancel | Cancel this tool and every pending tool |

Tools with `require_cmd_approval = true`, such as `run_command` and `delete_file`, are approved per command rather than per tool. If you always accept `make format`, you're still asked before `make test`.

Press `gtx` to reset the approvals for the chat buffer.

### Approval Modes

Press `gty` in the chat buffer to choose how tools are approved:

| Mode | Description |
| --- | --- |
| Ask | Approve each tool before it runs |
| Auto | Tools run without asking, apart from protected tools and commands that aren't on your safe list |
| YOLO | Everything runs without asking |

Every chat buffer starts in Ask. To start in a different mode:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        opts = {
          approval_mode = "auto", -- Can be "ask", "auto" or "yolo"
        },
      },
    },
  },
})
```

Resetting the approvals with `gtx` returns the chat buffer to this mode.

In Auto mode, a protected tool always asks first. `delete_file` is protected by default:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["delete_file"] = {
          opts = {
            protect = true,
          },
        },
      },
    },
  },
})
```

In Auto mode, `run_command` asks first unless the command is on its safe list:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["run_command"] = {
          opts = {
            safe_commands = { "git status", "git diff", "make test" },
          },
        },
      },
    },
  },
})
```

A command is safe if it starts with an entry on the list, so `git status` also covers `git status --short`. **A command that chains, nests or redirects, with `;`, `&`, `|`, `>`, `<`, `$(`, a backtick or a new line, is never treated as safe.**

> [!IMPORTANT]
> An entry covers every flag the command accepts. Only add commands whose flags can't write files or run other programs: `git diff --output=notes.txt` writes a file and `rg --pre` runs one

If you've enabled the [LLM judge](/configuration/tools#llm-judge), it decides on commands that aren't on the safe list instead of asking you.

A [prompt library](/configuration/prompt-library#options) item can start its chat buffer in a given mode with `opts.approval_mode = "auto"`.

Approval modes also apply to ACP agents. In Auto mode, reads, searches, edits and fetches are approved, and everything else asks. Any shell command is checked against the `run_command` safe list, even when the agent labels it as a read or a search.

> [!WARNING]
> YOLO mode runs every tool, including protected ones, without asking. Only use it where you can recover from lost data, as you're responsible for any damage it causes

## Compatibility

Tool use by adapter:

| Adapter | Supported | Notes |
| --- | :---: | --- |
| Anthropic | :white_check_mark: | Dependent on the model |
| Azure OpenAI | :white_check_mark: | Dependent on the model |
| Copilot | :white_check_mark: | Dependent on the model |
| DeepSeek | :white_check_mark: | Dependent on the model |
| Gemini | :white_check_mark: | Dependent on the model |
| Gemini (Legacy) | :white_check_mark: | Dependent on the model |
| Hugging Face | :white_check_mark: | Dependent on the model |
| Kimi | :white_check_mark: | Dependent on the model |
| Mistral | :white_check_mark: | Dependent on the model |
| Novita | :white_check_mark: | Dependent on the model |
| Ollama | :white_check_mark: | Dependent on the model. Tested with Qwen3 |
| OpenAI | :white_check_mark: | Dependent on the model |
| OpenAI (Legacy) | :white_check_mark: | Dependent on the model |
| OpenRouter | :white_check_mark: | Dependent on the model |
| xAI | :x: | Not supported yet |

<style scoped>
table td:first-child code {
  white-space: nowrap;
}
</style>
