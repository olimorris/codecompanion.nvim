---
description: Configure ruiles (such as CLAUDE.md. AGENTS.md or Cursor rules) in CodeCompanion
---

# Configuring Rules

Within CodeCompanion, rules fulfil two main purposes within a chat buffer:

1. To provide system-level instructions to your LLM
2. To provide persistent context via files in your project

Similar to Cursor's [Rules](https://cursor.com/docs/context/rules), they provide a way to guide the behavior of your LLM within a chat. Why? LLMs don't retain memory between sessions so preferences and context need to be re-applied each time a new chat is started.

## Enabling Rules

:::tabs

== Enable

```lua
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

== With Conditions

```lua
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

In the plugin, rule groups are a collection of files and/or directories that can be loaded into the chat buffer.

:::tabs

== Example Group

```lua
require("codecompanion").setup({
  rules = {
    claude = {
      description = "Rule files for Claude Code users",
      files = {
        -- Paths can be absolute or relative to the cwd
        "~/.claude/CLAUDE.md",
        "CLAUDE.md",
        "CLAUDE.local.md",
      },
    },
  },
})
```

== With Conditions

```lua
require("codecompanion").setup({
  rules = {
    CodeCompanion = {
      description = "CodeCompanion plugin rule files",
      parser = "claude",
      ---@return boolean
      enabled = function()
        -- Don't show this to users who aren't working on CodeCompanion itself
        return vim.fn.getcwd():find("codecompanion", 1, true) ~= nil
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

== Nested Groups

```lua
require("codecompanion").setup({
  rules = {
    CodeCompanion = {
      description = "CodeCompanion plugin rule files",
      parser = "claude",
      files = {
        ["acp"] = {
          description = "The ACP implementation",
          files = {
            ".codecompanion/acp/acp.md",
          },
        },
      },
    },
  },
})
```

== Setting Default Groups

```lua
require("codecompanion").setup({
  rules = {
    opts = {
      chat = {
        default_rules = "default",
        -- Or, set multiple default groups
        --default_rules = { "default", "another_new_group" },
      },
    },
  },
})
```

:::

Nested groups allow you to apply the same conditional to multiple groups alongside keeping your config clean. In the example above, the main group is `CodeCompanion` and a sub-group, `acp`, sits within the files table. The `claude` parser sits across all of the groups.

When using the _Action Palette_ or the slash command, the plugin will extract these nested groups and display them.

You can also set default groups that are automatically applied to all chat buffers. This is useful for ensuring that your preferred rules are always available.

## Parsers

Parsers allow CodeCompanion to transform rules, affecting how they are shared in the chat buffer. This is particularly useful if you reference files in your rules. Currently, the plugin has two in-built parsers:

- `claude` - which will import files into the chat buffer in the same way Claude Code [does](https://docs.anthropic.com/en/docs/claude-code/memory#claude-md-imports). Note, this requires rules to be `markdown` files
- `CodeCompanion` - parses rules in the same ways as `claude` but allows for a system prompts to be extracted via a H2 "System Prompt" header
- `none` - a blank parser which can be used to overwrite parsers that have been set on the default rules groups

Please see the guide on [Creating Rules Parsers](/extending/parsers) to understand how you can create and apply your own.

### Applying Parsers

You can apply parsers at a group level, to ensure that all files in the group are parsed in the same way. Alternatively, you can apply them at a file level to have more granular control.

::: tabs

== Group Level

```lua
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

== File Level

```lua
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

== Disable

```lua
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

