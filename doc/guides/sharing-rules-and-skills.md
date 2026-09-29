---
description: "Give the LLM your conventions once, with rules files like AGENTS.md and CLAUDE.md and with skills, and have them apply in every project."
---

# Sharing Rules and Skills Across Projects

An LLM forgets your conventions the moment a chat ends. CodeCompanion gives you two ways to hand them over once: _rules_, which are files added to every new chat, and _skills_, which the LLM only reads in full when a task calls for them.

## Rules Already in Your Project

If your project has an `AGENTS.md` or `CLAUDE.md`, there's nothing to configure. Every new chat buffer loads the `default` rule group, which picks up whichever of these files exist:

| File | Location |
|---|---|
| `AGENTS.md`, `AGENT.md` | Current working directory |
| `CLAUDE.md`, `CLAUDE.local.md` | Current working directory |
| `~/.claude/CLAUDE.md` | Your home directory |
| `.github/copilot-instructions.md` | Current working directory |
| `.cursorrules`, `.clinerules`, `.windsurfrules`, `.goosehints`, `.rules` | Current working directory |

Files that don't exist are skipped. `@path` imports inside `AGENTS.md` and `CLAUDE.md` are followed, so a line like `@docs/STYLE.md` shares that file too. See [Using Rules](/usage/chat-buffer/rules) for how the paths are resolved.

Cursor's newer `.cursor/rules` directory isn't in the `default` group. To add it alongside the defaults, create a group for it and autoload both:

```lua
require("codecompanion").setup({
  rules = {
    cursor = {
      description = "Cursor rules",
      files = {
        ".cursor/rules/**/*.mdc",
      },
    },
    opts = {
      chat = {
        autoload = { "default", "cursor" },
      },
    },
  },
})
```

A glob matches nothing in a project without the directory, so this is safe to leave on everywhere. Cursor's frontmatter, such as `globs` and `alwaysApply`, isn't interpreted - every matching file is shared in full.

<img src="https://github.com/user-attachments/assets/25102b7c-38f9-4802-8fc9-78010bf08b6e" alt="Rules in the chat buffer" />

## Personal Rules in Every Project

`~/.claude/CLAUDE.md` is already loaded everywhere. If you'd rather keep your own conventions outside of Claude's directory, put them in a group of their own and autoload it after `default`:

```lua
require("codecompanion").setup({
  rules = {
    personal = {
      description = "My conventions for every project",
      files = {
        { path = "~/.config/codecompanion/rules", files = "*.md" },
      },
    },
    opts = {
      chat = {
        autoload = { "default", "personal" },
      },
    },
  },
})
```

Groups are loaded in the order they're listed, and a file that appears in more than one group is only added once. `~/.config/codecompanion/rules` isn't a location CodeCompanion knows about - it's just a directory you create. Any path works.

To load a group only in certain projects, make `autoload` a function:

```lua
require("codecompanion").setup({
  rules = {
    opts = {
      chat = {
        ---@return string|string[]
        autoload = function()
          if vim.fn.getcwd():find("work", 1, true) then
            return { "default", "personal", "work" }
          end
          return { "default", "personal" }
        end,
      },
    },
  },
})
```

Any group can also be added to an open chat with the [/rules](/usage/chat-buffer/slash-commands#rules) slash command, and `gM` removes every rule from the chat. See [Configuring Rules](/configuration/rules) for directories, nested groups and parsers.

## Different Rules for Different Adapters

`rules.opts.chat.enabled` can be a function. It's called with the chat when the chat is created, so you can check the adapter:

```lua
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

This skips rules entirely for [agents](/configuration/adapters-acp), which is what you want if the agent already reads `CLAUDE.md` or `AGENTS.md` itself. Check `chat.adapter.name`, such as `"claude_code"` or `"codex"`, to target one agent.

> [!NOTE]
> `enabled` is only checked when the chat is created. Switching adapter in an open chat doesn't add or remove rules

## Skills

A _skill_ is a folder with a `SKILL.md` inside, following [Claude's format](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview#how-skills-work). Only its name and description go into the chat. The LLM reads the rest with the `read_file` tool when it decides the skill applies, so a long skill costs almost nothing until it's used.

CodeCompanion looks for skills in these directories, and a later one wins if two skills share a name:

| Directory | Scope |
|---|---|
| `~/.config/codecompanion/skills` | Personal |
| `.codecompanion/skills` | Project |
| `~/.agents/skills` | Personal, shared with other agents |
| `~/.claude/skills` | Personal, shared with Claude Code |
| `.claude/skills` | Project, shared with Claude Code |

So a skill in `~/.claude/skills` is already available, and a project's `.claude/skills` overrides a personal skill of the same name. Skills sit one level down, as `<dir>/<skill-name>/SKILL.md`.

**The LLM only knows about the skills you add to the chat.** Add them with the [/skills](/usage/chat-buffer/slash-commands#skills) slash command, or have some added to every chat:

```lua
require("codecompanion").setup({
  skills = {
    opts = {
      chat = {
        autoload = { "lua-developer", "code-review" },
      },
    },
  },
})
```

`autoload` takes skill names or [group](/configuration/skills#groups) names, and a group can be added in one go with [/skills-group](/usage/chat-buffer/slash-commands#skills-group). Descriptions can span several lines using YAML's `>` folded style:

```markdown
---
name: lua-developer
description: >
  The Lua conventions for this project.
  Use when writing or reviewing Lua.
---
```

See [Configuring Skills](/configuration/skills) for the full set of options and [Creating Skills](/configuration/skills#creating-skills) for how to write one.

## Agents

Agents like Claude Code and Codex bring their own way of loading project instructions, so it's worth knowing what CodeCompanion adds on top:

- **Rules** - Loaded by default, and sent to the agent as text with your first message. A system prompt taken from a rules file isn't sent, as agents don't take one
- **Skills** - Not added. `/skills` and `/skills-group` are hidden, and `autoload` is skipped. Use the agent's own skills through the `\` trigger instead, as covered in [Skills on ACP Adapters](/usage/chat-buffer/skills#acp-adapters)

If your agent already reads `CLAUDE.md` or `AGENTS.md`, turn rules off for agents with the [`enabled` function above](#different-rules-for-different-adapters) so the file isn't sent twice.

## Rules, Skills, System Prompts or Prompts

| Use | When | Applies to |
|---|---|---|
| Rules | The LLM should always know it, like coding style or project layout | Every chat, or the chats you add it to |
| Skills | The LLM needs it for certain tasks, like writing a migration or a release | Chats you add it to, read only when relevant |
| [System prompt](/configuration/system-prompt#changing-system-prompts) | You want to change how the LLM behaves in every chat, whatever the project | Every chat with an http adapter |
| [Prompt library](/usage/prompt-library) | You repeat the same request, like writing a commit message | The chat you start from the prompt |

A prompt library item can name its own rules and skills, so a prompt like "Review this PR" can always bring your `code-review` skill with it. See [rules in prompts](/configuration/prompt-library) and [skills in prompts](/configuration/skills#prompt-library).

## Limitations

- Skills need the Tree-sitter `yaml` parser. Run `:TSInstall yaml` if `/skills` shows nothing
- Skills need an http adapter with tool use. They're not added for a model that has tools turned off
- A group's own `enabled` function only hides it from `/rules` and the Action Palette. It doesn't stop the group being autoloaded, so use an `autoload` function for that
