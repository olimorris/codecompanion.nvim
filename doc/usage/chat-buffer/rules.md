---
description: Learn how to get the most out of rules in CodeCompanion
---

# Using Rules

Ensure that you have read the [Rules Configuration](/configuration/rules) section to understand how to create and configure rule groups.

## Default Rule Group

Below is the `default` rule group that, when [enabled](/configuration/rules#enabling-rules), provides a collection of common files to the chat buffer:

```lua
require("codecompanion").setup({
  rules = {
    default = {
      description = "Collection of common files for all projects",
      files = {
        ".clinerules",
        ".cursorrules",
        ".goosehints",
        ".rules",
        ".windsurfrules",
        ".github/copilot-instructions.md",
        "AGENT.md",
        "AGENTS.md",
        { path = "CLAUDE.md", parser = "claude" },
        { path = "CLAUDE.local.md", parser = "claude" },
        { path = "~/.claude/CLAUDE.md", parser = "claude" },
      },
    },
  },
})
```

## Creating Rules

The plugin does not require rules to be in a specific filetype or even format (unless you're using the `claude` parser). This allows you to leverage [mdc](https://docs.cursor.com/en/context/rules#rule-anatomy) files, markdown files or good old plain text files.

The location of the rules is also unimportant. The rules files could be local to the project you're working in. Or, they could reside in a separate location on your disk. Just ensure the path is correct when you're [creating/configuring](/configuration/rules#rule-groups) the rules group.

### Example 1: Rule that can be processed with the `codecompanion` parser

```markdown
# Example Rules File

## System Prompt

What ever goes in this section is used as a system prompt in the chat buffer.

So you can specify instructions:
- Here
- And here

...and anywhere here

## My other header

@./lua/codecompanion/strategies/chat/tools/init.lua

Anything in this section is added as context to the chat buffer. The file above is also shared
```

### Example 2: Rule that can be processed with the `claude` parser

```markdown
# Example Claude Rules File

@./lua/codecompanion/strategies/chat/tools/init.lua

This is a rules file that can be parsed with the Claude parser.

Anything in this file is added as context to the chat buffer.

Including the file above.
```

## Adding Rules to a Chat Buffer

### When Opening the Chat Buffer

Rules can automatically be added to a chat buffer when it's created. Just specify the default rules to include:

::: tabs

== Default Rules

```lua
require("codecompanion").setup({
  rules = {
    opts = {
      chat = {
        default_rules = { "default", "claude "}
      },
    },
  },
})
```

== Overwriting the Default Rules Group

```lua
require("codecompanion").setup({
  rules = {
    default = {
      description = "My default group",
      files = {
        "CLAUDE.md",
        "~/Code/Helpers/my_project_specific_help.md",
      },
    },
    opts = {
      chat = {
        default_rules = "default",
      },
    },
  },
})
```

:::

### Slash Command

To add rules to an existing chat buffer, use the `/rules` slash command. This will allow multiple rule groups to be added at a time.

### Action Palette

<img src="https://github.com/user-attachments/assets/09ecd976-ac8b-446f-bed3-a8122617eb79">

There is also a _Chat with rules_ action in the [Action Palette](/usage/action-palette). This lists all of the rule groups in the config that can be added to a new chat buffer.

### Clearing Rules

Rules can also be cleared from a chat buffer via the `gR` keymap. Although note, this will remove _ALL_ context that's been designated as _rules_.

