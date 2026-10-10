---
description: "Write your own prompts for the prompt library, in Markdown or Lua, and run them from the Action Palette, a keymap or a slash command."
---

# Configuring the Prompt Library

The _prompt library_ holds reusable prompts that you run from the [Action Palette](/usage/action-palette), a keymap, the command line or the chat buffer. CodeCompanion ships with some, and you can add your own as Markdown files or Lua tables.

## Adding Prompts

Point CodeCompanion at directories of Markdown files, or define prompts as Lua tables in your config:

::: code-group

```lua [Markdown]
require("codecompanion").setup({
  prompt_library = {
    markdown = {
      dirs = {
        vim.fn.getcwd() .. "/.prompts",
        "~/.dotfiles/.config/prompts",
      },
    },
  },
})
```

```lua [Lua]
require("codecompanion").setup({
  prompt_library = {
    ["Docusaurus"] = {
      interaction = "chat",
      description = "Write documentation for me",
      prompts = {
        {
          role = "user",
          content = "Write documentation for the selected code in Docusaurus format.",
        },
      },
    },
  },
})
```

:::

Directories can be relative or absolute, and a directory can also be a function that receives the [buffer context](#placeholders) and returns a path. Files can be nested up to five directories deep. Symlinked files are loaded, but symlinked directories aren't followed.

### Refreshing Markdown Prompts

To pick up Markdown prompts you've added or changed since Neovim started:

```
:CodeCompanionActions Refresh
```

## Creating Prompts

A prompt is a series of messages sent to an LLM. Markdown is easier to read and maintain, as there's no string escaping or concatenation, and a prompt can share Lua helper files with others in the same directory.

### Structure

A prompt that explains the selected code:

::: code-group

````markdown [Markdown]
---
name: Explain Code
interaction: chat
description: Explain how code works
---

## system

You are an expert programmer who excels at explaining code clearly and concisely.

## user

Please explain the following code:

```${context.filetype}
${context.code}
```
````

```lua [Lua]
require("codecompanion").setup({
  prompt_library = {
    ["Explain Code"] = {
      interaction = "chat",
      description = "Explain how code works",
      prompts = {
        {
          role = "system",
          content = "You are an expert programmer who excels at explaining code clearly and concisely.",
        },
        {
          role = "user",
          content = function(context)
            local text = require("codecompanion.helpers.code").get_code(context.start_line, context.end_line)
            return "Please explain the following code:\n\n````" .. context.filetype .. "\n" .. text .. "\n````"
          end,
        },
      },
    },
  },
})
```

:::

A Markdown prompt has YAML frontmatter between `---` delimiters, then a `## system` or `## user` heading for each message. The frontmatter fields are:

| Field | Required | Description |
| --- | --- | --- |
| `name` | Yes | The name shown in the Action Palette |
| `interaction` | Yes | `chat`, `inline` or `workflow` |
| `description` | No | The description shown in the Action Palette |
| `opts` | No | See [Options](#options) |
| `context` | No | See [Context](#context) |
| `mcp_servers` | No | See [MCP Servers](#mcp-servers) |
| `rules` | No | See [Rules](#rules) |
| `skills` | No | See [Skills](#skills) |
| `tools` | No | See [Tools](#tools) |

In a Lua prompt, the table key is the name. The `${context.filetype}` and `${context.code}` above are [placeholders](#placeholders).

### Options

A prompt that generates unit tests in a new buffer:

::: code-group

```markdown [Markdown]
---
name: Generate Tests
interaction: inline
description: Generate unit tests
opts:
  alias: tests
  auto_submit: true
  modes:
    - v
  placement: new
  stop_context_insertion: true
---

## system

Generate comprehensive unit tests for the provided code.

## user

The code to generate tests for is #{buffer}
```

```lua [Lua]
require("codecompanion").setup({
  prompt_library = {
    ["Generate Tests"] = {
      interaction = "inline",
      description = "Generate unit tests",
      opts = {
        alias = "tests",
        auto_submit = true,
        modes = { "v" },
        placement = "new",
        stop_context_insertion = true,
      },
      prompts = {
        {
          role = "system",
          content = "Generate comprehensive unit tests for the provided code.",
        },
        {
          role = "user",
          content = "The code to generate tests for is #{buffer}",
        },
      },
    },
  },
})
```

:::

The available options are:

| Option | Type | Description |
| --- | --- | --- |
| `adapter` | table | The adapter and model to use, as below |
| `alias` | string | Run the prompt with `:CodeCompanion /{alias}` or `require("codecompanion").prompt("{alias}")` |
| `approval_mode` | string | Start the chat buffer in an [approval mode](/usage/chat-buffer/agents-tools#approval-modes): `"ask"`, `"auto"` or `"yolo"` |
| `auto_submit` | boolean | Send the prompt to the LLM straight away |
| `callbacks` | table | [Callbacks](/configuration/callbacks) for the chat buffer the prompt opens (Lua only) |
| `enabled` | boolean | Set to `false` to hide the prompt without removing it |
| `ignore_system_prompt` | boolean | Don't send the [system prompt](/configuration/system-prompt) with the chat |
| `intro_message` | string | The intro message shown in the chat buffer |
| `is_slash_cmd` | boolean | Make a chat prompt available as a slash command, using its `alias` |
| `is_workflow` | boolean | Treat the prompt as a [workflow](#workflows) |
| `modes` | table | Only show the prompt in these modes, such as `{ "v" }` for visual mode |
| `placement` | string | For the inline interaction: `new`, `replace`, `add`, `before` or `chat` |
| `pre_hook` | function | Run before the prompt, see [Pre-hooks](#pre-hooks) (Lua only) |
| `stop_context_insertion` | boolean | Don't add the visual selection to the prompt automatically |
| `user_prompt` | boolean | Ask for your input before the prompt runs |

To use a different adapter and model:

::: code-group

```markdown [Markdown]
---
name: Local Review
interaction: chat
description: Review code with a local model
opts:
  adapter:
    name: ollama
    model: deepseek-coder:6.7b
---
```

```lua [Lua]
require("codecompanion").setup({
  prompt_library = {
    ["Local Review"] = {
      interaction = "chat",
      description = "Review code with a local model",
      opts = {
        adapter = {
          name = "ollama",
          model = "deepseek-coder:6.7b",
        },
      },
    },
  },
})
```

:::

[ACP adapters](/configuration/adapters-acp) also take `acp_opts`, which sets [session config options](https://agentclientprotocol.com/protocol/session-config-options#session-config-options). Keys are the option's `category`, and values are the option's `value` or its `name`, case-insensitively:

::: code-group

```markdown [Markdown]
---
name: Quick Review
interaction: chat
description: Fast review with low effort
opts:
  adapter:
    name: claude_code
    model: Opus
    acp_opts:
      mode: plan
      thought_level: low
---
```

```lua [Lua]
require("codecompanion").setup({
  prompt_library = {
    ["Quick Review"] = {
      interaction = "chat",
      description = "Fast review with low effort",
      opts = {
        adapter = {
          name = "claude_code",
          model = "Opus",
          acp_opts = {
            mode = "plan",
            thought_level = "low",
          },
        },
      },
    },
  },
})
```

:::

> [!TIP]
> To see the options an agent supports, open a chat with that adapter and press `gd` for the debug window

### Placeholders

Placeholders add dynamic content to a prompt with `${name}`. In Lua, `content` can also be a function that receives the buffer context.

**Context**

`${context.<field>}` reads from the buffer the prompt was started from:

::: code-group

```markdown [Markdown]
---
name: Buffer Info
interaction: chat
description: Show buffer information
---

## user

I'm working in buffer ${context.bufnr} which is a ${context.filetype} file.
```

```lua [Lua]
require("codecompanion").setup({
  prompt_library = {
    ["Buffer Info"] = {
      interaction = "chat",
      description = "Show buffer information",
      prompts = {
        {
          role = "user",
          content = function(context)
            return "I'm working in buffer " .. context.bufnr .. " which is a " .. context.filetype .. " file."
          end,
        },
      },
    },
  },
})
```

:::

The fields, with a visual selection of lines 8 to 10:

```lua
{
  bufnr = 7,
  buftype = "",
  code = [[local function hello(text)
    return "hello " .. text
  end]],
  cursor_pos = { 10, 3 },
  end_col = 3,
  end_line = 10,
  filename = "hello.lua",
  filetype = "lua",
  is_normal = false,
  is_visual = true,
  line_count = 42,
  lines = { "local function hello(text)", '  return "hello " .. text', "end" },
  mode = "v",
  path = "/Users/Oli/Code/project/lua/hello.lua",
  relative_path = "lua/hello.lua",
  start_col = 1,
  start_line = 8,
  user_prompt = "",
  winnr = 1000,
}
```

Without a selection, `code` is `false` and `lines` is empty.

**External Lua Files**

`${file.key}` loads `file.lua` from the prompt's directory and reads `key` from the table it returns:

```
.prompts/
├── commit.md
├── commit.lua
└── utils.lua
```

::: code-group

````markdown [commit.md]
---
name: Commit message
interaction: chat
description: Generate a commit message
opts:
  alias: commit
---

## user

You are an expert at following the Conventional Commit specification. Given the git diff listed below, please generate a commit message for me:

```diff
${commit.diff}
```
````

```lua [commit.lua]
return {
  diff = function(args)
    return vim.system({ "git", "diff", "--no-ext-diff", "--staged" }, { text = true }):wait().stdout
  end,
}
```

:::

A prompt can reference as many files as it likes, such as `${commit.diff}` and `${utils.git_log}` together. A value can be a string, or a function that receives an `args` table and returns one:

```lua
return {
  summary = function(args)
    -- args.context is the buffer context and args.item is the whole prompt
    return "Working in " .. args.context.relative_path
  end,
  style = "Keep the summary to one line",
}
```

## Conditionals

In Lua, a `condition` function controls whether a prompt appears in the Action Palette, or whether a single message is sent:

::: code-group

```lua [Prompt]
require("codecompanion").setup({
  prompt_library = {
    ["Visual Only"] = {
      interaction = "chat",
      description = "Only appears in visual mode",
      condition = function(context)
        return context.is_visual
      end,
      prompts = {
        {
          role = "user",
          content = "This prompt only appears when you're in visual mode.",
        },
      },
    },
  },
})
```

```lua [Message]
require("codecompanion").setup({
  prompt_library = {
    ["Visual Only"] = {
      interaction = "chat",
      description = "Only sends the message in visual mode",
      prompts = {
        {
          role = "user",
          content = "This message is only sent when you're in visual mode.",
          condition = function(context)
            return context.is_visual
          end,
        },
      },
    },
  },
})
```

:::

## Context

To start a chat buffer with files, symbols or URLs already shared:

::: code-group

```markdown [Markdown]
---
name: Test Context
interaction: chat
description: Add some context
context:
  - type: file
    path:
      - lua/codecompanion/health.lua
      - lua/codecompanion/http.lua
  - type: symbols
    path: lua/codecompanion/interactions/chat/init.lua
  - type: url
    url: https://raw.githubusercontent.com/olimorris/codecompanion.nvim/refs/heads/main/lua/codecompanion/commands.lua
---

## user

Explain how these files fit together.
```

```lua [Lua]
require("codecompanion").setup({
  prompt_library = {
    ["Test Context"] = {
      interaction = "chat",
      description = "Add some context",
      context = {
        {
          type = "file",
          path = {
            "lua/codecompanion/health.lua",
            "lua/codecompanion/http.lua",
          },
        },
        {
          type = "symbols",
          path = "lua/codecompanion/interactions/chat/init.lua",
        },
        {
          type = "url",
          url = "https://raw.githubusercontent.com/olimorris/codecompanion.nvim/refs/heads/main/lua/codecompanion/commands.lua",
        },
      },
      prompts = {
        {
          role = "user",
          content = "Explain how these files fit together.",
          opts = {
            contains_code = true,
          },
        },
      },
    },
  },
})
```

:::

`path` and `url` take a single value or a list. URLs are fetched each time the prompt runs. A message with `contains_code = true` is left out when `opts.send_code` is `false`.

## MCP Servers

To start [MCP servers](/configuration/mcp) with the prompt:

::: code-group

```markdown [Markdown]
---
name: Prompt with MCP servers
interaction: chat
description: A prompt that starts MCP servers
mcp_servers:
  - tavily-mcp
  - filesystem
---
```

```lua [Lua]
require("codecompanion").setup({
  prompt_library = {
    ["Prompt with MCP servers"] = {
      interaction = "chat",
      description = "A prompt that starts MCP servers",
      mcp_servers = {
        "tavily-mcp",
        "filesystem",
      },
    },
  },
})
```

:::

These replace the servers that have `add_to_chat = true`. Set `mcp_servers` to `none` to start no servers at all.

## Pickers

In Lua, a picker opens a second menu of items built at runtime:

```lua
require("codecompanion").setup({
  prompt_library = {
    ["My picker menu ..."] = {
      interaction = " ",
      description = "My current items",
      picker = {
        prompt = "Select an item",
        columns = { "name", "description" },
        items = {
          {
            name = "Item 1",
            description = "This is item 1",
            callback = function(context)
              print("You selected item 1")
            end,
          },
          {
            name = "Item 2",
            description = "This is item 2",
            callback = function(context)
              print("You selected item 2")
            end,
          },
        },
      },
    },
  },
})
```

`items` can also be a function that receives the buffer context and returns the list.

## Pre-hooks

In Lua, `pre_hook` runs before the prompt. In the inline interaction with `placement = "new"`, it must return the number of the buffer to write the code into:

```lua
require("codecompanion").setup({
  prompt_library = {
    ["Boilerplate HTML"] = {
      interaction = "inline",
      description = "Generate some boilerplate HTML",
      opts = {
        placement = "new",
        pre_hook = function()
          local bufnr = vim.api.nvim_create_buf(true, false)
          vim.api.nvim_set_current_buf(bufnr)
          vim.api.nvim_set_option_value("filetype", "html", { buf = bufnr })
          return bufnr
        end,
      },
      prompts = {
        {
          role = "system",
          content = "You are an expert HTML programmer",
        },
        {
          role = "user",
          content = "Please generate some HTML boilerplate for me. Return the code only and no markdown codeblocks",
        },
      },
    },
  },
})
```

## Rules

To load [rule groups](/configuration/rules#rule-groups) with the prompt:

::: code-group

```markdown [Markdown]
---
name: Prompt with rules
interaction: chat
description: A prompt that loads rules
rules:
  - default
  - my_other_rules
---
```

```lua [Lua]
require("codecompanion").setup({
  prompt_library = {
    ["Prompt with rules"] = {
      interaction = "chat",
      description = "A prompt that loads rules",
      rules = {
        "default",
        "my_other_rules",
      },
    },
  },
})
```

:::

Set `rules` to `none` to load no rules at all.

> [!NOTE]
> A prompt that names no rules loads none by default. Enable `rules.opts.chat.autoload_groups_in_prompt_library` to load the groups in `rules.opts.chat.autoload` instead

## Skills

To load [skills](/configuration/skills#prompt-library), or skill groups, with the prompt:

::: code-group

```markdown [Markdown]
---
name: Review this PR
interaction: chat
description: Review the changes on this branch
skills:
  - code-review
---
```

```lua [Lua]
require("codecompanion").setup({
  prompt_library = {
    ["Review this PR"] = {
      interaction = "chat",
      description = "Review the changes on this branch",
      skills = { "code-review" },
    },
  },
})
```

:::

These replace the skills in `autoload`. Set `skills` to `none` to load no skills at all.

## Tools

To load [tools](/configuration/tools), or tool groups, with the prompt:

::: code-group

```markdown [Markdown]
---
name: Prompt with tools
interaction: chat
description: A prompt that loads tools
tools:
  - run_command
  - edit_file
---
```

```lua [Lua]
require("codecompanion").setup({
  prompt_library = {
    ["Prompt with tools"] = {
      interaction = "chat",
      description = "A prompt that loads tools",
      tools = {
        "run_command",
        "edit_file",
      },
    },
  },
})
```

:::

These are added alongside the [default tools](/configuration/tools#default-tools). Set `tools` to `none` to load no tools at all, including the defaults.

## Workflows

A _workflow_ chains prompts together. The first prompt is sent to the LLM, and once it responds, the next is added to the chat buffer, and so on. Use one for multi-step work such as writing code, then its tests:

::: code-group

```markdown [Markdown]
---
name: Library workflow
interaction: chat
description: Build and test a library class
opts:
  adapter:
    name: copilot
    model: gpt-4.1
  is_workflow: true
---

## user

Generate a Python class for managing a book library with methods for adding, removing and searching books

## user

Write unit tests for the library class you just created

## user

Add type hints and docstrings to the class and its tests
```

```lua [Lua]
require("codecompanion").setup({
  prompt_library = {
    ["Library workflow"] = {
      interaction = "chat",
      description = "Build and test a library class",
      opts = {
        adapter = {
          name = "copilot",
          model = "gpt-4.1",
        },
        is_workflow = true,
      },
      prompts = {
        {
          {
            role = "user",
            content = "Generate a Python class for managing a book library with methods for adding, removing and searching books",
          },
        },
        {
          {
            role = "user",
            content = "Write unit tests for the library class you just created",
          },
        },
        {
          {
            role = "user",
            content = "Add type hints and docstrings to the class and its tests",
          },
        },
      },
    },
  },
})
```

:::

In Lua, each inner table is one step. In Markdown, each `## user` heading is a step, and any `## system` messages are sent with the first.

To change the options for a single step, such as submitting it automatically or switching model, give it its own `opts`. In Markdown, add a `yaml opts` code block under the heading:

::: code-group

````markdown [Markdown]
## user

Generate a Python class for managing a book library with methods for adding, removing and searching books

## user

```yaml opts
auto_submit: true
```

Write unit tests for the library class you just created

## user

```yaml opts
adapter:
  name: copilot
  model: claude-haiku-4.5
auto_submit: false
```

Add type hints and docstrings to the class and its tests
````

```lua [Lua]
prompts = {
  {
    {
      role = "user",
      content = "Generate a Python class for managing a book library with methods for adding, removing and searching books",
    },
  },
  {
    {
      role = "user",
      content = "Write unit tests for the library class you just created",
      opts = {
        auto_submit = true,
      },
    },
  },
  {
    {
      role = "user",
      content = "Add type hints and docstrings to the class and its tests",
      opts = {
        adapter = {
          name = "copilot",
          model = "claude-haiku-4.5",
        },
        auto_submit = false,
      },
    },
  },
},
```

:::

> [!NOTE]
> Markdown prompts don't support [agentic workflows](/extending/agentic-workflows), which need Lua

## Hiding Built-in Prompts

To hide the prompts that ship with CodeCompanion from the Action Palette:

```lua
require("codecompanion").setup({
  display = {
    action_palette = {
      opts = {
        show_preset_prompts = false,
      },
    },
  },
})
```

## Limitations

Workflows ignore the `ignore_system_prompt`, `intro_message`, `pre_hook`, `stop_context_insertion` and `user_prompt` options.
