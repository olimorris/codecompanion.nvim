---
description: "Create rule groups from files such as AGENTS.md, CLAUDE.md and Cursor rules, choose which load with every chat and set how they're parsed."
---

# Configuring Rules

LLMs don't remember anything between chats, so your instructions and project context have to be shared again each time. _Rules_ are the files that hold them, such as `AGENTS.md` or `CLAUDE.md`, and CodeCompanion collects them into _rule groups_ that are added to the chat buffer. To use them in a chat and write your own, see [Using Rules](/usage/chat-buffer/rules).

## Enabling Rules

Rules are enabled by default, and the `default` group is added to every new chat buffer. To turn them off, or only add them to some chats:

::: code-group

```lua [Disable]
require("codecompanion").setup({
  rules = {
    opts = {
      chat = {
        enabled = false,
      },
    },
  },
})
```

```lua [Conditional]
require("codecompanion").setup({
  rules = {
    opts = {
      chat = {
        ---@param chat CodeCompanion.Chat
        ---@return boolean
        enabled = function(chat)
          return chat.adapter.type == "http"
        end,
      },
    },
  },
})
```

:::

### Default Group

The `default` group looks for these files, and skips any that don't exist:

| File | Used By | Parser |
| --- | --- | --- |
| `.clinerules` | Cline | |
| `.cursorrules` | Cursor | |
| `.goosehints` | Goose | |
| `.rules` | Zed | |
| `.windsurfrules` | Windsurf | |
| `.github/copilot-instructions.md` | Copilot | |
| `AGENT.md` | Agents | `claude` |
| `AGENTS.md` | Agents | `claude` |
| `CLAUDE.md` | Claude Code | `claude` |
| `CLAUDE.local.md` | Claude Code | `claude` |
| `~/.claude/CLAUDE.md` | Claude Code | `claude` |

Relative paths are looked up from the current working directory. To replace the group, define your own `default` in `rules`.

## Rule Groups

A _rule group_ is a named list of files and directories:

```lua
require("codecompanion").setup({
  rules = {
    my_project_rules = {
      description = "Rule files for My Project",
      files = {
        "CLAUDE.md",
        "~/.claude/CLAUDE.md",
        "docs/**/*.md",
        { path = "CLAUDE.local.md", parser = "claude" },
        { path = "~/.config/rules", files = "*.md" },
      },
    },
  },
})
```

Each entry in `files` can be:

| Entry | Example | Adds |
| --- | --- | --- |
| A path | `"CLAUDE.md"` | The file, or every file in it if it's a directory |
| A glob | `"docs/**/*.md"` | Every matching file |
| A path with a parser | `{ path = "CLAUDE.local.md", parser = "claude" }` | The file, read with that [parser](#parsers) |
| A directory with patterns | `{ path = ".", files = { ".clinerules", "*.md" } }` | Files in the directory matching a pattern |

Paths can be absolute or relative to the current working directory. A directory with patterns can take a `parser` too, which applies to every file it matches.

### Conditional Groups

`enabled` hides a group from the [/rules](/usage/chat-buffer/slash-commands#rules) slash command and the _Chat with rules ..._ action when it returns `false`:

```lua
require("codecompanion").setup({
  rules = {
    my_project_rules = {
      description = "Rule files for My Project",
      ---@return boolean
      enabled = function()
        return vim.fn.getcwd():find("my_project", 1, true) ~= nil
      end,
      files = {
        "CLAUDE.md",
        "CLAUDE.local.md",
      },
    },
  },
})
```

### Nested Groups

A group's `files` can hold other groups instead of a list, so one `enabled` condition and `parser` apply to all of them:

```lua
require("codecompanion").setup({
  rules = {
    my_project_rules = {
      description = "Rule files for My Project",
      parser = "claude",
      files = {
        ["mcp"] = {
          description = "The MCP implementation in My Project",
          files = {
            ".rules/mcp/mcp.md",
          },
        },
        ["tests"] = {
          description = "How tests are written in My Project",
          files = {
            ".rules/tests.md",
          },
        },
      },
    },
  },
})
```

The slash command and the action list each nested group separately, as `my_project_rules/mcp` and `my_project_rules/tests`. CodeCompanion's own `CodeCompanion` group does this, with a group for each part of the plugin, and only appears when the current working directory has a `.codecompanion` directory.

To hide the preset `default` and `CodeCompanion` groups from the list:

```lua
require("codecompanion").setup({
  rules = {
    opts = {
      show_presets = false,
    },
  },
})
```

## Autoload

Groups in `autoload` are added to every new chat buffer. It defaults to `"default"`:

::: code-group

```lua [Single Group]
require("codecompanion").setup({
  rules = {
    opts = {
      chat = {
        autoload = "my_project_rules",
      },
    },
  },
})
```

```lua [Multiple Groups]
require("codecompanion").setup({
  rules = {
    opts = {
      chat = {
        autoload = { "default", "my_project_rules" },
      },
    },
  },
})
```

```lua [Conditional]
require("codecompanion").setup({
  rules = {
    opts = {
      chat = {
        ---@return string|string[]
        autoload = function()
          if vim.fn.getcwd():find("another_project", 1, true) ~= nil then
            return { "my_project", "another_project" }
          end
          return "my_project"
        end,
      },
    },
  },
})
```

:::

### Prompt Library

A [prompt library](/configuration/prompt-library) item only gets rules if it names them in its own `rules` field. To give the items that name none your `autoload` groups:

```lua
require("codecompanion").setup({
  rules = {
    opts = {
      chat = {
        autoload_groups_in_prompt_library = true,
      },
    },
  },
})
```

An item that names its own rules still uses those instead, and `rules = "none"` loads none.

## Parsers

A _parser_ changes how a rules file is shared with the LLM. Without one, the file is shared as it is. The built-in parsers are:

| Parser | Description |
| --- | --- |
| `claude` | Share the whole file, plus any file it references on an `@` line, like Claude Code [does](https://code.claude.com/docs/en/memory#claude-md-imports) |
| `codecompanion` | Share the content under `##` headings and any `@` files, and use a `## System Prompt` section as the system prompt |
| `cli` | Share only the paths of `@` files. Used by the `/rules` slash command in the [CLI interaction](/usage/cli) |
| `none` | Share the file unchanged |

The `claude` and `codecompanion` parsers need markdown files. How `@` paths are resolved is covered in [Resolving `@` Paths](/usage/chat-buffer/rules#resolving-paths). To write your own, see [Creating Rules Parsers](/extending/parsers).

### Applying Parsers

A parser can be set on a group, to apply to every file in it, or on a single file. A file's parser takes precedence over its group's:

::: code-group

```lua [Group Level]
require("codecompanion").setup({
  rules = {
    claude = {
      description = "Rules for Claude Code users",
      parser = "claude",
      files = {
        "CLAUDE.md",
        "CLAUDE.local.md",
        "~/.claude/CLAUDE.md",
      },
    },
  },
})
```

```lua [File Level]
require("codecompanion").setup({
  rules = {
    claude = {
      description = "Rules for Claude Code users",
      files = {
        { path = "CLAUDE.md", parser = "claude" },
        { path = "CLAUDE.local.md", parser = "claude" },
        { path = "~/.claude/CLAUDE.md", parser = "claude" },
      },
    },
  },
})
```

```lua [Disable]
require("codecompanion").setup({
  rules = {
    claude = {
      description = "Rules for Claude Code users",
      parser = "none",
      files = {
        "CLAUDE.md",
        "CLAUDE.local.md",
        "~/.claude/CLAUDE.md",
      },
    },
  },
})
```

:::

## Syncing Referenced Files

A file referenced on an `@` line that's open in a buffer is [synced](/usage/chat-buffer/#context) to the chat buffer, sending only what's changed on each turn. To send its entire content instead:

```lua
require("codecompanion").setup({
  rules = {
    opts = {
      chat = {
        default_params = "all", -- Can be "all" or "diff"
      },
    },
  },
})
```
