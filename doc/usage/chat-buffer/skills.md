---
description: "Write and use agent skills in the CodeCompanion chat buffer — SKILL.md folders your LLM reads on demand, compatible with Claude Code skills."
---

# Using Skills

> [!IMPORTANT]
> Skills are only available for [http](/configuration/adapters-http) adapters. [ACP](/configuration/adapters-acp) agents *may* have skills implemented which can be accessed via the `\` trigger. See [Skills on ACP Adapters](/usage/chat-buffer/skills#acp-adapters) for more information.

Ensure that you have read the [Skills Configuration](/configuration/skills) section to understand how to configure skill directories and groups.

## What Your LLM Sees

Adding a skill to a chat buffer shares the skill's metadata (the YAML frontmatter in `SKILL.md`) with the LLM:

```
The `lua-developer` skill is available: The Lua conventions for this project. Use when writing or reviewing Lua.
Read `/Users/Oli/.config/codecompanion/skills/lua-developer/SKILL.md` when the skill applies and follow its instructions.
```

By only loading the metadata, the context in the chat buffer is kept small.

To read the skill in full, CodeCompanion attaches the `read_file` and `run_command` [tools](/usage/chat-buffer/agents-tools) to the chat. As a result, you'll need to use an LLM which has function calling capability.

## Adding Skills

The [/skills](/usage/chat-buffer/slash-commands#skills) slash command lists every skill found in the [skill directories](/configuration/skills#directories). Multiple skills can be added at once depending on the picker you've defined in the config.

The [/skills-group](/usage/chat-buffer/slash-commands#skills-group) slash command lists your configured [groups](/configuration/skills#groups) and adds all of their skills to the chat buffer.

CodeCompanion detects whether you have [telescope](https://github.com/nvim-telescope/telescope.nvim), [fzf_lua](https://github.com/ibhagwan/fzf-lua), [mini_pick](https://github.com/echasnovski/mini.pick) or [snacks.nvim](https://github.com/folke/snacks.nvim) installed and picks one for you. Failing that, it falls back to the `default` provider, `vim.ui.select`, which is the only one that can't select more than one skill at a time.

Each command is configured separately:

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

Everything above applies to [http](/configuration/adapters-http) adapters. On an [ACP](/configuration/adapters-acp) adapter such as Claude Code, the agent runs its own skills, so `/skills` and `/skills-group` are hidden.

Reach the agent's skills with the `\` trigger instead, which lists the [ACP commands](/usage/chat-buffer/#completion) the agent has discovered for itself. A skill in `~/.claude/skills` is therefore available either way: through `/skills` when you're on an http adapter, and through `\` when Claude Code is driving.

## Removing a Skill

A skill can be removed from the chat buffer by deleting the skill's line from the _Context_ blockquote in the chat buffer.
