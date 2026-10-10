---
description: "Add your own tools and tool groups, control approvals, set default tools and configure the LLM judge and web search."
---

# Configuring Tools

_Tools_ let an LLM act on your machine, such as running shell commands or editing files. Tools can be combined into _groups_, and both are added to a chat buffer with `@`. To use them, see [Using Agents and Tools](/usage/chat-buffer/agents-tools).

## Adding Tools

Tools live under `interactions.chat.tools`. To add your own:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["my_tool"] = {
          description = "Run a custom task",
          path = "user.codecompanion.tools.my_tool",
        },
      },
    },
  },
})
```

A tool resolves to a [`CodeCompanion.Tool`](/extending/tools) table, from one of:

- **`path`** - A Lua module path or a path to a Lua file that returns the table
- **`callback`** - A function that returns the table
- **The entry itself** - The tool table, written inline

## Tool Groups

A _tool group_ bundles tools together, with an optional system prompt telling the LLM how to use them:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        groups = {
          ["my_group"] = {
            description = "A custom agent combining tools",
            system_prompt = "Run the test suite after every edit",
            tools = {
              "run_command",
              "edit_file",
            },
            opts = {
              collapse_tools = true,
              ignore_system_prompt = false,
              ignore_tool_system_prompt = false,
            },
          },
        },
      },
    },
  },
})
```

`system_prompt` can also be a function that receives the group's config and a [context object](/configuration/system-prompt), with fields such as `language`, `date`, `nvim_version` and `os`.

| Option | Default | Description |
| --- | --- | --- |
| `collapse_tools` | `true` | Show the group as a single context item rather than one per tool |
| `ignore_system_prompt` | `false` | Remove the chat buffer's system prompt |
| `ignore_tool_system_prompt` | `false` | Remove the tool system prompt |

## Enabling Tools

`enabled` hides a tool when it returns `false`, such as when a dependency isn't installed. After installing one, refresh the tools in the chat buffer with:

```
:CodeCompanionChat RefreshCache
```

This works for the built-in tools and for an adapter's own tools:

::: code-group

```lua [Built-in Tools]
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["grep_search"] = {
          ---@param opts { adapter: CodeCompanion.HTTPAdapter }
          ---@return boolean
          enabled = function(opts)
            return vim.fn.executable("rg") == 1
          end,
        },
      },
    },
  },
})
```

```lua [Adapter Tools]
require("codecompanion").setup({
  adapters = {
    http = {
      openai = function()
        return require("codecompanion.adapters").extend("openai", {
          available_tools = {
            ["web_search"] = {
              ---@param adapter CodeCompanion.HTTPAdapter
              ---@return boolean
              enabled = function(adapter)
                return false
              end,
            },
          },
        })
      end,
    },
  },
})
```

:::

## Approvals

Approvals stop a tool from running until you've agreed to it. How they work in the chat buffer is covered in [Approvals](/usage/chat-buffer/agents-tools#approvals). To require approval before a tool runs:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["run_command"] = {
          opts = {
            require_approval_before = true,
          },
        },
      },
    },
  },
})
```

The approval options are:

| Option | Description |
| --- | --- |
| `require_approval_before` | Ask before the tool runs. Can also be a function that receives the tool and returns a boolean |
| `require_cmd_approval` | Approve each command rather than the tool as a whole |
| `protect` | Always ask in Auto mode |
| `judge` | Let the [LLM judge](#llm-judge) decide in Auto mode |
| `safe_commands` | Commands that run without asking in Auto mode. `run_command` only |

The defaults for each built-in tool are listed in [Built-in Tools](/usage/chat-buffer/agents-tools#built-in-tools).

## Default Tools

To add tools and tool groups to every new chat buffer:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        opts = {
          default_tools = {
            "my_tool",
            "my_group",
          },
        },
      },
    },
  },
})
```

This also works for tools from [extensions](/configuration/extensions).

## Limiting Tool Output

A large tool output can fill a model's context window. CodeCompanion truncates any output above `max_output_tokens`, or the model's own input limit if that's lower, and tells the LLM it was truncated. To change the limit:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        opts = {
          max_output_tokens = 30000,
        },
      },
    },
  },
})
```

## LLM Judge

In [Auto mode](/usage/chat-buffer/agents-tools#approval-modes), a command that isn't on the `run_command` safe list asks you first. The _LLM judge_ sits in between: a [background interaction](/guides/background-model) judges the action and only asks you when it's judged unsafe. To turn it on for `run_command`:

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

The judge runs for a tool when:

- `interactions.background.gates.judge.enabled` is `true`, which is the default
- The tool has `opts.judge = true`
- The tool defines a `gates.judge_context` handler, as `run_command` and `delete_file` do

It never runs for a protected tool, and if it can't reach a verdict, it asks you. The judge uses the background interaction's adapter unless you give it one:

::: code-group

```lua [Adapter]
require("codecompanion").setup({
  interactions = {
    background = {
      gates = {
        judge = {
          adapter = { name = "openrouter", model = "openai/gpt-oss-120b" },
        },
      },
    },
  },
})
```

```lua [System Prompt]
require("codecompanion").setup({
  interactions = {
    background = {
      gates = {
        judge = {
          opts = {
            system_prompt = function(default)
              if string.find(vim.fn.getcwd(), "Code/Neovim/codecompanion.nvim") then
                return default
                  .. "\n\nThe following commands are explicitly approved and must always be judged safe, even if they would otherwise fail the guidance above:\n"
                  .. "  - `make docs`\n"
                  .. "  - `make format`\n"
                  .. "  - `make test`\n"
                  .. "  - `make test_file` (including any `FILE=` argument)"
              end
              return default
            end,
          },
        },
      },
    },
  },
})
```

:::

`system_prompt` can be a string, or a function that receives the default system prompt and returns a string. The default is:

```
You are a security reviewer for an AI coding assistant. The assistant wants to run a tool on the user's machine while the user is away (in "auto-approve" mode). Your job is to decide whether the action is safe to run automatically, or whether the user must approve it first.

Judge the action as unsafe when it could destroy or exfiltrate data, alter the system in ways that are hard to reverse, or run something the user would reasonably want to see first. Prefer caution: when in doubt, require approval.

Reply only through the provided schema.
```

## Web Search

The [web_search](/usage/chat-buffer/agents-tools#web-search) tool searches with an adapter:

| Adapter | Description |
| --- | --- |
| `duckduckgo` | The default, with no API key needed |
| `jina` | API key optional |
| `serply` | Needs `SERPLY_API_KEY` |
| `tavily` | Needs `TAVILY_API_KEY` |

To change the adapter, and pass options to it:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["web_search"] = {
          opts = {
            adapter = "tavily",
            opts = {
              search_depth = "advanced",
              topic = "general",
              chunks_per_source = 3,
              max_results = 5,
            },
          },
        },
      },
    },
  },
})
```

The options each adapter accepts are in its file in [lua/codecompanion/adapters/http](https://github.com/olimorris/codecompanion.nvim/tree/main/lua/codecompanion/adapters/http).
