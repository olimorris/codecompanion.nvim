---
description: "Configure CodeCompanion's tools in Neovim, covering tool groups, approvals, YOLO mode, the LLM judge, default tools and output limits."
---

# Configuring Tools

[Tools](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua#L55) perform specific tasks (e.g., running shell commands, editing buffers, etc.) when invoked by an LLM. Multiple tools can be grouped together. Both can be referenced with `@` (by default), when in the chat buffer:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["my_tool"] = {
          description = "Run a custom task",
          callback = require("user.codecompanion.tools.my_tool")
        },
        groups = {
          ["my_group"] = {
            description = "A custom agent combining tools",
            system_prompt = "Describe what the agent should do",
            tools = {
              "run_command",
              "insert_edit_into_file",
              -- Add your own tools or reuse existing ones
            },
            opts = {
              collapse_tools = true, -- When true, show as a single group reference instead of individual tools
              ignore_system_prompt = false, -- When true, remove the chat's default system prompt
              ignore_tool_system_prompt = false, -- When true, remove the default tool system prompt
            },
          },
        },
      },
    },
  },
})
```

When users introduce the group, `my_group`, in the chat buffer, it can call the tools you listed (such as `run_command`) to perform tasks on your code. The `system_prompt` field allows you to give the LLM specific instructions for how to use the group's tools and can be a string or a function that receives the group config table and a [context object](/configuration/system-prompt) (with `language`, `date`, `nvim_version`, `os`, etc.).

A tool is a [`CodeCompanion.Tool`](/extending/tools) table with specific keys that define the interface and workflow of the tool. The table can be resolved using the `callback` option. The `callback` option can be a table itself or either a function or a string that points to a luafile that return the table.

## Enabling Tools

Tools can be conditionally enabled using the `enabled` option. This works for built-in tools as well as an adapter's own tools. This is useful to ensure that a particular dependency is installed on the machine. You can use the `:CodeCompanionChat RefreshCache` command if you've installed a new dependency and want to refresh the tool availability in the chat buffer.

::: code-group

```lua [Enable Built-in Tools]
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["grep_search"] = {
          ---@param adapter CodeCompanion.HTTPAdapter
          ---@return boolean
          enabled = function(adapter)
            return vim.fn.executable("rg") == 1
          end,
        },
      }
    }
  }
})
```

```lua [Enable Adapter Tools]
require("codecompanion").setup({
  openai_responses = function()
    return require("codecompanion.adapters").extend("openai_responses", {
      available_tools = {
        ["web_search"] = {
          ---@param adapter CodeCompanion.HTTPAdapter
          enabled = function(adapter)
            return false
          end,
        },
      },
    })
  end,
})
```

:::

## Approvals

CodeCompanion allows you to apply safety mechanisms to its built-in tools prior to execution. See the [approvals usage](/usage/chat-buffer/agents-tools#approvals) section for more information.

::: code-group

```lua [Require Approval] {7}
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

```lua [Require Cmd Approval] {7}
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["run_command"] = {
          opts = {
            require_cmd_approval = true,
          },
        },
      },
    },
  },
})
```

```lua [No YOLO'ing] {7}
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["run_command"] = {
          opts = {
            allowed_in_yolo_mode = false,
          },
        },
      },
    },
  },
})
```

:::

## Auto Submit (Recursion)

When a tool executes, it can be useful to automatically send its output back to the LLM. This is turned on by default and can be configured with:

```lua {6-7}
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        opts = {
          auto_submit_errors = true, -- Send any errors to the LLM automatically?
          auto_submit_success = true, -- Send any successful output to the LLM automatically?
        },
      }
    }
  }
})
```

## Default Tools

You can configure the plugin to automatically add tools and tool groups to new chat buffers:

```lua {6-9}
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        opts = {
          default_tools = {
            "my_tool",
            "my_tool_group"
          }
        },
      }
    }
  }
})
```

This also works for [extensions](/configuration/extensions).

## Limiting Tool Output

To prevent the output from a tool exceeding the context window of a model, CodeCompanion will look to use the lower of a specified `max_output_tokens` limit or a model's own prompt limit. Should the tool exceed the limit, CodeCompanion will truncate the output and notify the LLM in the response.

The limit can be configured with:

```lua {6}
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        opts = {
          max_output_tokens = 30000, -- Truncate a tool's output above this many tokens
        },
      }
    }
  }
})
```

## LLM Judge

When [YOLO mode](/usage/chat-buffer/agents-tools#yolo-mode) is on, tools are auto-approved. Some tools (such as `run_command` and `delete_file`), by default, will always ask you first, owing to their destructive nature. The judge offers a middle ground: a background LLM judges the specific action and only interrupts you when it is judged to be unsafe.

To fully enable the LLM judge:

```lua
require("codecompanion").setup({
  interactions = {
    background = {
      gates = {
        judge = {
          enabled = true,
        },
      },
    },
    chat = {
      tools = {
        ["delete_file"] = {
          opts = {
            judge_in_yolo_mode = true,
          },
        },
        ["run_command"] = {
          opts = {
            judge_in_yolo_mode = true,
          },
        },
      },
    },
  },
})
```

The judge runs for a tool only when:

- You set `background.gates.judge.enabled = true`
- You set `opts.judge_in_yolo_mode = true` on the tool's config; _and_
- The tool defines a `gates.judge_context` handler (already the case for the built-in `run_command` and `delete_file` tools)

Below are some additional configuration options for the judge:

::: code-group

```lua [Specific Adapter]
require("codecompanion").setup({
  interactions = {
    background = {
      gates = {
        judge = {
          enabled = true,
          -- Specify a specific adapter and model for the judge to use
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
          enabled = true,
          opts = {
            system_prompt = function(default)
              -- A specific system prompt for a specific project
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

> [!NOTE]
> The system prompt can be a string or a function that receives the default system prompt and returns a string

The default system prompt for the judge is:

```
You are a security reviewer for an AI coding assistant. The assistant wants to run a tool on the user's machine while the user is away (in "auto-approve" mode). Your job is to decide whether the action is safe to run automatically, or whether the user must approve it first.

Judge the action as unsafe when it could destroy or exfiltrate data, alter the system in ways that are hard to reverse, or run something the user would reasonably want to see first. Prefer caution: when in doubt, require approval.

Reply only through the provided schema.
```

See the [YOLO mode](/usage/chat-buffer/agents-tools#yolo-mode) usage section for how the judge behaves once enabled.

## Web Search

The [web_search](/usage/chat-buffer/agents-tools#web-search) tool is a built-in tool that allows an LLM to perform web searches using an adapter. Currently, CodeCompanion supports [DuckDuckGo](https://duckduckgo.com), [Jina](https://www.jina.ai) and [Tavily](https://www.tavily.com) adapters.

To override the default Tavily adapter:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["web_search"] = {
          opts = {
            adapter = "duckduckgo",
          },
        },
      },
    },
  },
})
```

For additional options, refer to the adapter's own file.
