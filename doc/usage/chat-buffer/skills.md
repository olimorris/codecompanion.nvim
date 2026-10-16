---
description: "Add agent skills to the chat buffer, so an LLM can read their instructions when a task calls for them."
---

# Using Skills

> [!IMPORTANT]
> Skills are only available on [HTTP adapters](/configuration/adapters-http). On [ACP adapters](/configuration/adapters-acp), use the agent's own skills through the `\` trigger, as covered in [ACP Adapters](#acp-adapters)

A _skill_ is a folder with a `SKILL.md` file of instructions for a specific task. CodeCompanion shares each skill's name and description with the LLM, which reads the full file only when the skill applies.

To set up skill directories and groups, see [Configuring Skills](/configuration/skills).

## What Your LLM Sees

Adding a skill shares the `name` and `description` from the YAML frontmatter in its `SKILL.md`:

```
The `lua-developer` skill is available: The Lua conventions for this project. Use when writing or reviewing Lua.
Read `/Users/Oli/.config/codecompanion/skills/lua-developer/SKILL.md` when the skill applies and follow its instructions.
```

Sharing only the frontmatter keeps the chat buffer's context small.

To read the full skill, CodeCompanion adds the `read_file` [tool](/usage/chat-buffer/agents-tools) to the chat, and `run_command` if it's enabled. The model must support function calling.

> [!NOTE]
> If the `read_file` tool is disabled in your config, the skill isn't added and a warning is logged

## Adding Skills

The [/skills](/usage/chat-buffer/slash-commands#skills) slash command lists every skill in your [skill directories](/configuration/skills#directories). The [/skills-group](/usage/chat-buffer/slash-commands#skills-group) slash command lists your [groups](/configuration/skills#groups) and adds all of a group's skills. It's hidden until you configure a group.

To add skills to every new chat, see [Autoload](/configuration/skills#autoload).

### Pickers

CodeCompanion uses [Telescope](https://github.com/nvim-telescope/telescope.nvim), [fzf-lua](https://github.com/ibhagwan/fzf-lua), [mini.pick](https://github.com/echasnovski/mini.pick) or [Snacks](https://github.com/folke/snacks.nvim), in that order, depending on which is installed. Without any of them, it falls back to `vim.ui.select`, which only selects one skill at a time.

Each slash command sets its picker separately:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      slash_commands = {
        ["skills"] = {
          opts = {
            provider = "snacks", -- Can be "default", "telescope", "fzf_lua", "mini_pick" or "snacks"
          },
        },
        ["skills-group"] = {
          opts = {
            provider = "snacks",
          },
        },
      },
    },
  },
})
```

## ACP Adapters

On an [ACP adapter](/configuration/adapters-acp) such as Claude Code, the agent runs its own skills, so `/skills` and `/skills-group` are hidden.

Use the `\` trigger instead. It lists the [ACP commands](/usage/chat-buffer/#completion) the agent has found for itself. A skill in `~/.claude/skills` is available either way: through `/skills` on an HTTP adapter, and through `\` when Claude Code is the agent.

## Removing a Skill

Delete the skill's line from the _Context_ blockquote in the chat buffer.
