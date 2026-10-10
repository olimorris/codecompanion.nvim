---
description: "Choose where CodeCompanion finds SKILL.md files, group skills together and load them into every chat."
---

# Configuring Skills

_Skills_ are folders of instructions that an LLM reads when it needs them ([source](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)). CodeCompanion only gives the LLM each skill's name and description up front, and the LLM reads the full skill when it applies. This is _progressive disclosure_, and it's why a chat can hold many skills without filling its context window.

CodeCompanion uses the same `SKILL.md` [format as Claude](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview#how-skills-work). To use skills in a chat, see [Using Skills](/usage/chat-buffer/skills).

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

Skills are loaded from `skills.dirs`, which defaults to:

| Directory | Description |
| --- | --- |
| `~/.config/codecompanion/skills` | Your personal skills |
| `.codecompanion/skills` | The project's skills |
| `~/.agents/skills` | Personal skills shared with other agents |
| `~/.claude/skills` | Claude Code's personal skills |
| `.claude/skills` | Claude Code's project skills |

To change them:

```lua
require("codecompanion").setup({
  skills = {
    dirs = {
      "~/.config/codecompanion/skills",
      ".codecompanion/skills",
      "~/Code/team-skills",
    },
  },
})
```

Skills are keyed on the `name` in their YAML frontmatter. A directory further down the list takes precedence if skills of the same name clash, which also means a directory symlinked to another doesn't duplicate its skills.

A `SKILL.md` is found up to five directories deep, so you can clone a repository of skills straight into a skills directory. Hidden directories such as `.git` are skipped. To change the depth:

```lua
require("codecompanion").setup({
  skills = {
    opts = {
      depth = 3,
    },
  },
})
```

Skills aren't cached, so new ones are picked up without restarting Neovim.

## Groups

A _group_ adds several skills under one name. Groups sit alongside `dirs` in the `skills` table:

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

A group lists skills by the `name` in their frontmatter, not by path, so each skill must be in one of your [directories](#directories).

## Autoload

To add skills and groups to every new chat buffer:

::: code-group

```lua [Static]
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

```lua [Conditional]
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

The inline interaction has its own `autoload`, covered in [Configuring the Inline Interaction](/configuration/inline#rules-and-skills).

## Creating Skills

A skill is a directory containing a `SKILL.md`, in one of your [directories](#directories):

```
lua-developer/
├── SKILL.md          # Required
├── REFERENCE.md      # Optional
└── scripts/          # Optional
    └── lint.sh
```

`SKILL.md` is markdown with YAML frontmatter, as described on Claude's [Agent Skills](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview#how-skills-work) page. Both `name` and `description` are required:

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

The LLM only sees the description until it reads the skill, so a vague description means the skill may never be used.

Link to other files in the skill with paths relative to `SKILL.md`. The LLM is given the full path to `SKILL.md`, so it finds them wherever you started Neovim from.

## Pickers

The [/skills](/usage/chat-buffer/slash-commands#skills) and [/skills-group](/usage/chat-buffer/slash-commands#skills-group) slash commands use Telescope, fzf-lua, mini.pick or Snacks, whichever is installed first in that order, and fall back to `vim.ui.select`. To choose one:

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

A [prompt library](/configuration/prompt-library) item can name the skills it needs, and they're added to the chat buffer when the prompt runs. These replace `autoload` for that chat:

::: code-group

```markdown [Markdown]
---
name: Review this PR
interaction: chat
description: Review the changes on this branch
skills:
  - code-review
---

## user

Review the changes in #{diff}.
```

```lua [Lua]
require("codecompanion").setup({
  prompt_library = {
    ["Review this PR"] = {
      interaction = "chat",
      description = "Review the changes on this branch",
      skills = { "code-review" },
      prompts = {
        {
          role = "user",
          content = "Review the changes in #{diff}.",
        },
      },
    },
  },
})
```

:::

To start a prompt with no skills at all, ignoring `autoload`:

::: code-group

```markdown [Markdown]
---
name: Explain this code
interaction: chat
description: Explain the selected code
skills: none
---

## user

Explain how the selected code works.
```

```lua [Lua]
require("codecompanion").setup({
  prompt_library = {
    ["Explain this code"] = {
      interaction = "chat",
      description = "Explain the selected code",
      skills = "none",
      prompts = {
        {
          role = "user",
          content = "Explain how the selected code works.",
        },
      },
    },
  },
})
```

:::

## Limitations

- Skills only work with HTTP adapters that support tools, so they're unavailable with ACP adapters
- The LLM reads a skill with the `read_file` tool, so a skill isn't added if that tool is disabled. `run_command` is added too, when it's enabled, so the LLM can run a skill's scripts
- Reading the frontmatter needs the Tree-sitter YAML parser. Install it with `:TSInstall yaml`
