---
description: "Configure agent skills in CodeCompanion — SKILL.md directories that give your LLM domain-specific knowledge, loaded on demand, in Neovim."
---

# Configuring Skills

Skills are reusable, filesystem-based resources that give LLMs domain-specific expertise ([source](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)). In CodeCompanion, skills are folders of repeatable instructions that your LLM reads when it needs them.

At initialisation, the LLM only receives the skills name and description. During a conversation, if the LLM deduces that the skill is required, then it reads the skill fully. This is known as progressive disclosure and it's what allows many skills to be present in the chat without consuming significant context.

CodeCompanion uses the same `SKILL.md` [format as Claude](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview#how-skills-work).

## Enabling and Disabling Skills

Skills are enabled by default. To disable them:

```lua
require("codecompanion").setup({
  skills = {
    opts = {
      chat = {
        enabled = false,
      },
    },
  },
})
```

## Directories

By passing in a list of directories, CodeCompanion will search for skills in each of them. They can be customised with:

```lua
require("codecompanion").setup({
  skills = {
    dirs = {
      "~/.config/codecompanion/skills", -- Personal skills
      ".codecompanion/skills",          -- Project skills
      "~/.claude/skills",               -- Claude Code's personal skills
      ".claude/skills",                 -- Claude Code's project skills
    },
  },
})
```

The directories are searched in order and skills are keyed on the `name` in their frontmatter. This results in a directory further down the list taking precedence if skills of the same name clash. This also means that if you symlink one skills directory to another and list both, you get one entry per skill rather than two.

CodeCompanion never caches skills so they can be added throughout the Neovim session without restarting.

## Groups

Groups allow you to group collective skills together under a single name for use in the chat buffer. They can be customised with:

```lua
require("codecompanion").setup({
  skills = {
    ["Senior Engineer"] = {
      description = "How I want code written and reviewed",
      skills = { "lua-developer", "code-review", "tdd" },
    },
    ["Technical Writer"] = {
      description = "How I want the docs written",
      skills = { "docs-voice", "changelog" },
    },
  },
})
```

The skills in a group must reference the name of the skill as per its frontmatter and not the path to the skill. This means that the skill must exist in one of the directories listed in `dirs`.

## Autoload

Skills and groups can be autoloaded into the chat buffer on startup. This is configured with:

::: code-group

```lua{5} [Static]
require("codecompanion").setup({
  skills = {
    opts = {
      chat = {
        autoload = { "Senior Engineer", "lua-developer" },
      },
    },
  },
})
```

```lua{6-11} [Conditional]
require("codecompanion").setup({
  skills = {
    opts = {
      chat = {
        ---@return string[]
        autoload = function()
          if vim.fn.getcwd():find("my_project", 1, true) then
            return { "Senior Engineer" }
          end
          return {}
        end,
      },
    },
  },
})
```

:::

## Prompt Library

Skills can also be referenced in [prompt library](/configuration/prompt-library) items, ensuring that they are loaded in the chat buffer when the prompt is used.

> [!NOTE]
> The prompt library skills takes priority over `autoload`

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
      strategy = "chat",
      skills = { "code-review" },
      prompts = {
        -- Omitted for brevity
      },
    },
  },
})
```

:::

Set skills to `none` to start a prompt with no skills at all, overriding `autoload`:

::: code-group

```markdown [Markdown]
---
name: No skills prompt
interaction: chat
description: A prompt that loads no skills
skills: none
---
```

```lua [Lua]
require("codecompanion").setup({
  prompt_library = {
    ["No skills prompt"] = {
      strategy = "chat",
      skills = "none",
      prompts = {
        -- Omitted for brevity
      },
    },
  },
})
```

:::
