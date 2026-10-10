---
description: "Add rules files such as AGENTS.md, CLAUDE.md and Cursor rules to the chat buffer, giving an LLM persistent instructions and project context."
---

# Using Rules

LLMs don't remember anything between chats, so your instructions and project context have to be shared again each time. _Rules_ are the files that hold them, such as `AGENTS.md` or `CLAUDE.md`. CodeCompanion collects them into _rule groups_ and adds them to the chat buffer as context.

To create and configure rule groups, see [Configuring Rules](/configuration/rules).

## Default Rule Group

When [enabled](/configuration/rules#enabling-rules), the `default` group adds these files to the chat buffer. Files that don't exist are skipped:

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
        { path = "AGENT.md", parser = "claude" },
        { path = "AGENTS.md", parser = "claude" },
        { path = "CLAUDE.md", parser = "claude" },
        { path = "CLAUDE.local.md", parser = "claude" },
        { path = "~/.claude/CLAUDE.md", parser = "claude" },
      },
    },
  },
})
```

## Creating Rules

Rules can be markdown, [mdc](https://docs.cursor.com/en/context/rules#rule-anatomy) or plain text files. Only the `claude` and `codecompanion` [parsers](/configuration/rules#parsers) need markdown. Rules can live in your project or anywhere else on disk, as long as the path in the [rule group](/configuration/rules#rule-groups) is correct.

A rules file can share other files with `@path` on its own line, and the `codecompanion` parser can also set the chat buffer's system prompt:

::: code-group

```markdown [codecompanion]
# Example Rules File

## System Prompt

Everything in this section is used as the system prompt in the chat buffer.

So you can specify instructions:
- Here
- And here

## My Other Header

@./lua/codecompanion/interactions/chat/tools/init.lua

Everything in this section is added as context to the chat buffer, and the file above is shared too.
```

```markdown [claude]
# Example Claude Rules File

@./lua/codecompanion/interactions/chat/tools/init.lua
@INSTRUCTIONS.md

The whole of this file is added as context to the chat buffer.

The files above are shared too.
```

:::

The `codecompanion` parser only shares content under `##` headings, and removes the `@` lines from it. The `claude` parser shares the whole file, `@` lines included.

### Resolving `@` Paths

CodeCompanion looks for an `@` path in this order:

1. With the `claude` parser, relative to the directory of the rules file
2. Relative to the current working directory
3. As written, which covers absolute paths starting with `/` or `~`

If none of these exist, the file is skipped and a warning is logged.

For example, an `@RTK.md` line in `~/.claude/CLAUDE.md` resolves to `~/.claude/RTK.md`, wherever Neovim was started from.

## Adding Rules to a Chat Buffer

### Autoload

Rule groups in `autoload` are added to every new chat buffer. It defaults to `"default"`. To change it:

::: code-group

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

```lua [Replacing the Default Group]
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
        autoload = "default",
      },
    },
  },
})
```

:::

`autoload` also accepts a function. See [Autoload](/configuration/rules#autoload).

### Slash Command

The [/rules](/usage/chat-buffer/slash-commands#rules) slash command adds a rule group to an open chat buffer. It adds one group at a time, so run it again for another.

### Action Palette

<img src="https://github.com/user-attachments/assets/09ecd976-ac8b-446f-bed3-a8122617eb79" alt="Chat buffer action palette" />

The _Chat with rules ..._ action in the [Action Palette](/usage/action-palette) lists every rule group in your config and opens a new chat buffer with the one you pick.

### Clearing Rules

Press `gM` in the chat buffer to remove rules. **This removes every item added as rules, not only one group**.
