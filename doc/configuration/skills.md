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

Skills are loaded in CodeCompanion from a list of directories. The default directories are:

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

The directories are searched in order and skills are keyed on the `name` in their YAML frontmatter. A directory further down the list takes precedence if skills of the same name clash. This also means that if you symlink one skills directory to another, the skills are not duplicated.

CodeCompanion never caches skills so they can be added without restarting Neovim.

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

The skills in a group must reference the name of the skill as per its YAML frontmatter and not the path to the skill. This means that the skill must exist in one of the directories listed in `dirs`.

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

## Creating Skills

A skill is a directory containing a `SKILL.md`, in one of your configured [skill directories](/configuration/skills#directories):

```
lua-developer/
├── SKILL.md          # Required
├── REFERENCE.md      # Optional
└── scripts/          # Optional
    └── lint.sh
```

`SKILL.md` is a markdown file with a YAML frontmatter, as per the Claude [Agent Skills](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview#how-skills-work) page:

```markdown
---
name: lua-developer
description: The Lua conventions for this project. Use when writing or reviewing Lua.
---

# Lua Developer

Follow these conventions when writing Lua in this project:

- Two space indent, 120 columns
- `snake_case` for functions, `PascalCase` for classes

See [REFERENCE.md](REFERENCE.md) for worked examples.

Run [scripts/lint.sh](scripts/lint.sh) before you report the work as finished.
```

The instructions (the main body of the skill) should contain the information the LLM needs to follow the skill. However, a vague description may mean the LLM never calls the skill.

Link to other files in the skill using paths relative to `SKILL.md`. The LLM is given the full path to `SKILL.md`, so it finds them wherever you started Neovim from.

## Pickers

When selecting skills to load into the chat buffer, CodeCompanion detects whether you have [telescope](https://github.com/nvim-telescope/telescope.nvim), [fzf_lua](https://github.com/ibhagwan/fzf-lua), [mini_pick](https://github.com/echasnovski/mini.pick) or [snacks.nvim](https://github.com/folke/snacks.nvim) installed. Failing that, it falls back to the `default` provider, `vim.ui.select`.

This can be configured with:

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
