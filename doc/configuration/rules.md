---
description: Configure ruiles (such as CLAUDE.md. AGENTS.md or Cursor rules) in CodeCompanion
---

# Configuring Rules

Within CodeCompanion, rules fulfil two main purposes within a chat buffer:

1. To provide system-level instructions to your LLM
2. To provide persistent context via files in your project

Similar to Cursor's [Rules](https://cursor.com/docs/context/rules), they provide a way to guide the behavior of your LLM within a chat. Why? LLMs don't retain memory between sessions so preferences and context need to be re-applied each time a new chat is started.

## Enabling Rules

::: code-group

```lua [Enable]
require("codecompanion").setup({
  rules = {
    opts = {
      chat = {
        enabled = true,
      },
    },
  },
})
```

```lua [With Conditions]
require("codecompanion").setup({
  rules = {
    opts = {
      chat = {
        ---@param chat CodeCompanion.Chat
        ---@return boolean
        condition = function(chat)
          -- Only enable rules for non ACP chats
          return chat.adapter.type ~= "acp"
        end,
      },
    },
  },
})
```

:::

Once enabled, the plugin will look to load a common, or default, set of rules every time a chat buffer is created.

> [!INFO]
> Refer to the [config.lua](https://github.com/olimorris/codecompanion.nvim/blob/5807e0457111f0de267fc9a6543b41fae0f5c2b1/lua/codecompanion/config.lua#L1167-L1179) file for the full set of files included in the default group.

## Rule Groups

In the plugin, rule groups are a collection of files and/or directories that can be loaded into the chat buffer. Groups give you flexibility to create different sets of rules for different use-cases. For example, you may want a set of rules specifically for working with Claude Code or another for working with a specific project.

::: code-group

```lua [Basic Group]
require("codecompanion").setup({
  rules = {
    my_project_rules = { -- [!code focus:9]
      description = "Rule files for My Project",
      files = {
        -- Literal file paths (absolute or relative to cwd)
        "~/.claude/CLAUDE.md",
        "CLAUDE.md",
        "CLAUDE.local.md",
      },
    },
  },
})
```

```lua [Conditionals]
require("codecompanion").setup({
  rules = {
    my_project_rules = { -- [!code focus:13]
      description = "Rule files for My Project",
      ---@return boolean
      enabled = function()
        -- Don't show this group unless in a specific dir
        return vim.fn.getcwd():find("my_project", 1, true) ~= nil
      end,
      files = {
        "~/.claude/CLAUDE.md",
        "CLAUDE.md",
        "CLAUDE.local.md",
      },
    },
  },
})
```


```lua [Directories]
require("codecompanion").setup({
  rules = {
    my_project_rules = { -- [!code focus:19]
      description = "Rule files for My Project",
      files = {
        -- Specify dirs to search in (supports glob patterns and literals)
        {
          path = vim.fn.getcwd(),
          files = { ".clinerules", ".cursorrules", "*.md" }
        },
        {
          path = "~/.config/rules",
          files = "*.md"
        },

        -- Mix with literal file paths
        "~/.claude/CLAUDE.md",
        "CLAUDE.md",
        "CLAUDE.local.md",
      },
    },
  },
})
```

```lua [File Patterns]
require("codecompanion").setup({
  rules = {
    my_project_rules = { -- [!code focus:21]
      description = "Rule files for My Project",
      files = {
        -- 1. Literal file paths
        "CLAUDE.md",
        "~/.claude/CLAUDE.md",

        -- 2. File path with parser
        { path = "CLAUDE.local.md", parser = "claude" },

        -- 3. Directory with file patterns
        { path = ".", files = { ".clinerules", "*.md" } },

        -- 4. Directory with parser
        { path = "~/.config/rules", files = "*.md", parser = "claude" },

        -- 5. Glob patterns (searches filesystem)
        "docs/**/*.md",
        ".github/*.md",
      },
    },
  },
})
```

```lua [Nested Groups]
require("codecompanion").setup({
  rules = {
    my_project_rules = { -- [!code focus:12]
      description = "Rule files for My Project",
      parser = "claude",
      files = {
        ["mcp"] = {
          description = "The MCP implementation in My project",
          files = {
            ".rules/mcp/mcp.md",
          },
        },
      },
    },
  },
})
```

:::

Nested groups allow you to apply the same conditional to multiple groups alongside keeping your config clean. Infact, the plugin uses this itself. There is a `CodeCompanion` group with sub-groups for different parts of the plugin, allowing contributors to easily share context with an LLM when they're working on specific parts of the codebase.

When using the _Action Palette_ or the slash command, the plugin will extract these nested groups and display them in the `Chat with rules ...` menu.

You can also set default groups that are automatically applied to all chat buffers. This is useful for ensuring that your preferred rules are always available.

### Autoload

You can set specific rule groups that will be automatically added to chat buffers. This is useful for ensuring that your preferred rules are always available.

::: code-group

```lua{5} [Single Group]
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

```lua{5} [Multiple Groups]
require("codecompanion").setup({
  rules = {
    opts = {
      chat = {
        autoload = { "my_project_rules", "another_project" },
      },
    },
  },
})
```

```lua{6-11} [Conditional Groups]
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

## Parsers

Parsers allow CodeCompanion to transform rules, affecting how they are shared in the chat buffer. This is particularly useful if you reference files in your rules. Currently, the plugin has two in-built parsers:

- `claude` - which will import files into the chat buffer in the same way Claude Code [does](https://docs.anthropic.com/en/docs/claude-code/memory#claude-md-imports). Note, this requires rules to be `markdown` files
- `CodeCompanion` - parses rules in the same ways as `claude` but allows for a system prompts to be extracted via a H2 "System Prompt" header
- `none` - a blank parser which can be used to overwrite parsers that have been set on the default rules groups

Please see the guide on [Creating Rules Parsers](/extending/parsers) to understand how you can create and apply your own.

### Applying Parsers

You can apply parsers at a group level, to ensure that all files in the group are parsed in the same way. Alternatively, you can apply them at a file level to have more granular control.

::: code-group

```lua{5} [Group Level]
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

```lua{6-8} [File Level]
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

```lua{5} [Disable]
require("codecompanion").setup({
  rules = {
    claude = {
      description = "Rules for Claude Code users",
      parser = "none", -- Disable parsing for the entire group
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

