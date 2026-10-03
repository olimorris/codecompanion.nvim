---
description: "Decide which tools an LLM can run in CodeCompanion without asking, and which need your approval first."
---

# Controlling Tool Approvals

Once an LLM has [tools](/usage/chat-buffer/agents-tools), it can read files, edit code and run shell commands in your project. CodeCompanion lets you choose which of those it does freely and which it has to ask you about, per tool, per command and per chat buffer.

This page is organised around what you want to allow. For every option, see the [approvals reference](/usage/chat-buffer/agents-tools#approvals) and [tool configuration](/configuration/tools#approvals).

## What Asks by Default

Out of the box, every chat buffer starts in _Ask_ mode and the built-in tools behave like this:

| Tool | Before it runs | After it runs |
|---|---|---|
| `read_file`, `grep_search`, `memory` | Asks | - |
| `run_command` | Asks, for each command | - |
| `delete_file` | Asks, for each file | - |
| `create_file`, `edit_file` | Runs | Asks you to confirm the change |
| `file_search`, `get_changed_files`, `get_diagnostics`, `fetch_webpage`, `web_search` | Runs | - |

Approvals are remembered per chat buffer. Approving a tool in one chat doesn't approve it anywhere else.

## Answering a Prompt

When a tool needs approval, the chat buffer lists your options:

| Keymap | Option | What happens |
|---|---|---|
| `g1` | Always accept | Runs the tool, and doesn't ask again in this chat |
| `g2` | Accept | Runs the tool this once |
| `g3` | Reject | Skips the tool and asks you for a reason to send to the LLM |
| `g4` | Cancel | Skips this tool and every other pending tool call |

For `run_command` and `delete_file`, **Always accept only covers that exact command or file**. Approving `make format` doesn't approve `make test`.

<img src="https://github.com/user-attachments/assets/c5bcd1e9-f243-4282-8bcb-fcc180d339b6" alt="Approval for run_command tool" />

After `create_file` or `edit_file` produces a change, you're asked to confirm it. Small diffs are shown in the chat buffer and larger ones open in a floating window, which `gv` opens on demand. The same `g1` to `g4` keymaps apply, except that Cancel only discards this change. Always accept here means later edits from that tool in this chat are written without a diff.

These keymaps are shared across CodeCompanion and can be changed under `interactions.shared.keymaps`. See [Keymaps](/keymaps).

## Approval Modes

Press `gty` in the chat buffer to choose a mode for that chat:

| Mode | What runs without asking |
|---|---|
| Ask | Only the tools that don't require approval, as in the table above |
| Auto | Everything except `run_command`, which asks unless the command is on its safe list, and protected tools such as `delete_file` |
| YOLO | Everything |

Auto mode also skips the confirmation after an edit, so changes are written straight to disk. [Code Review](/usage/code-review) is the way to check them afterwards. In Auto and YOLO, tool results are always sent back to the LLM, whatever [auto submit](/configuration/tools#auto-submit-recursion) is set to.

<img src="https://github.com/user-attachments/assets/d43aedaa-797e-4e45-928b-6dd44063a8a5" alt="Approval modes" />

To start every chat buffer in a different mode:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        opts = {
          approval_mode = "auto", -- Can be "ask", "auto" or "yolo"
        },
      },
    },
  },
})
```

> [!WARNING]
> YOLO runs every tool without asking, including `delete_file` and any shell command. Only use it where you can recover from lost data

## Scenarios

### Editing Freely, Asking Before Commands

Auto mode already does this, and asks before deletions too. Emptying the safe list makes every shell command ask. Alternatively, stay in Ask mode and remove the prompts you don't want:

::: code-group

```lua [Auto Mode]
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["run_command"] = {
          opts = {
            safe_commands = {},
          },
        },
        opts = {
          approval_mode = "auto",
        },
      },
    },
  },
})
```

```lua [Ask Mode]
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["edit_file"] = {
          opts = {
            require_confirmation_after = false,
          },
        },
        ["read_file"] = {
          opts = {
            require_approval_before = false,
          },
        },
      },
    },
  },
})
```

:::

`edit_file` treats files that are open in Neovim differently from those that aren't. To be asked before the LLM edits a file you don't have open, but not a buffer you do:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["edit_file"] = {
          opts = {
            require_approval_before = {
              buffer = false,
              file = true,
            },
          },
        },
      },
    },
  },
})
```

### Never Asking for Certain Commands

In Auto mode, a command on the `run_command` safe list runs without asking. The default list is `git status`, `ls` and `pwd`, and your list replaces it:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["run_command"] = {
          opts = {
            safe_commands = { "git status", "git diff", "ls", "make test" },
          },
        },
      },
    },
  },
})
```

An entry covers any arguments after it, so `make test` also covers `make test FILE=tests/test_chat.lua`. A command containing `;`, `&`, `|`, `<`, `>`, `$(`, a backtick or a new line is never safe.

> [!IMPORTANT]
> Only add commands whose flags can't write files or run other programs - `git diff --output=notes.txt` writes a file

The safe list is ignored in Ask mode. There, press `g1` the first time a command is proposed and it won't be asked about again in that chat.

### Always Asking Before Deleting

`delete_file` is _protected_ by default, so it asks in both Ask and Auto mode. A protected tool behaves in Auto mode as it does in Ask. To protect another tool, such as `run_command` so that even safe commands ask:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["run_command"] = {
          opts = {
            protect = true,
          },
        },
      },
    },
  },
})
```

**YOLO mode ignores `protect`.**

### Letting an LLM Judge Commands

In Auto mode, a command that isn't on the safe list asks you. The _judge_ sends it to a background LLM first, which runs it if it's judged safe and only asks you if it isn't. The judge's reason is shown in the prompt. To turn it on for `run_command`:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["run_command"] = {
          opts = {
            judge = true,
          },
        },
      },
    },
  },
})
```

A command judged safe is remembered for the rest of the chat, as if you'd pressed `g1`. The judge only runs in Auto mode, and never for a protected tool. It's worth it when you want Auto mode for long tasks but can't predict which commands the LLM will need. See [LLM Judge](/configuration/tools#llm-judge) to choose its adapter and system prompt, and [Background Model](/guides/background-model) for the background interaction it uses.

### Running a Prompt Unattended

A [prompt library](/configuration/prompt-library#options) item can start its chat buffer in any mode with `approval_mode`, leaving your other chats in Ask:

::: code-group

```markdown [Markdown]
---
name: Fix Failing Tests
interaction: chat
description: Run the tests and fix whatever fails
opts:
  alias: fixtests
  approval_mode: yolo
tools:
  - agent
---

## user

Run `make test` and fix every failing test.
```

```lua [Lua]
require("codecompanion").setup({
  prompt_library = {
    ["Fix Failing Tests"] = {
      interaction = "chat",
      description = "Run the tests and fix whatever fails",
      opts = {
        alias = "fixtests",
        approval_mode = "yolo", -- Can be "ask", "auto" or "yolo"
      },
      tools = { "agent" },
      prompts = {
        {
          role = "user",
          content = "Run `make test` and fix every failing test.",
        },
      },
    },
  },
})
```

:::

> [!NOTE]
> The older `yolo_mode = true` option still works but starts the chat in Auto, not YOLO

### Resetting a Chat

Press `gtx` in the chat buffer to forget everything you've approved in it. This also returns the chat to the mode set by `approval_mode`.

## Notifications

When a tool needs approval and you're in a different buffer, CodeCompanion sends a "Tool approval required" notification. To turn it off:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        opts = {
          notify_on_approval = false,
        },
      },
    },
  },
})
```

## Agents

Agents such as Claude Code and Codex run their own tools and have their own permission systems, so the per-tool options above don't apply to them. Their permission requests appear in the chat buffer, and the approval mode still answers them for you: Auto allows reads, searches, edits and fetches, and checks shell commands against the `run_command` safe list, whilst YOLO allows everything. See [Coding with an Agent](/guides/coding-with-an-agent).

## Limitations

- Approvals and the mode are cleared when you close the chat buffer
- A safe list entry trusts every flag of that command, so it's only as safe as the commands you add
