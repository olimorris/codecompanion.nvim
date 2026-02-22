---
description: Configure CodeCompanion's native chat buffer, to enable Vim like coding with AI
---

# Configuring the Chat Buffer

By default, CodeCompanion provides a _chat_ interaction that uses a dedicated Neovim buffer for conversational interaction with your chosen LLM. This buffer can be customized according to your preferences.

Please refer to the [config.lua](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua#L42-L392) file for a full list of all configuration options.

## Changing Adapter

By default, CodeCompanion sets the _copilot_ adapter for the chat interaction. You can change this to be a _ACP_ or _HTTP_ adapter:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      adapter = {
        name = "anthropic",
        model = "claude-haiku-4-5-20251001"
      },
    },
  },
})
```

See the section on [ACP](/configuration/adapters-acp) and [HTTP](/configuration/adapters-http) for more information.

## Completion

By default, CodeCompanion will determine if you have one of [blink.cmp](https://github.com/saghen/blink.cmp), [nvim-cmp](https://github.com/hrsh7th/nvim-cmp), or [coc.nvim](https://github.com/neoclide/coc.nvim) installed, selecting it as the default provider. Failing this, the default completion engine will be used.

You can override this with:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      opts = {
        completion_provider = "blink", -- blink|cmp|coc|default
      }
    }
  }
})
```

### Prefixes

You can also customize the prefixes that trigger completions for [editor context](/usage/chat-buffer/editor-context), [slash commands](/usage/chat-buffer/slash-commands), and [tools](/usage/chat-buffer/tools):

```lua
require("codecompanion").setup({
  opts = {
    triggers = {
      acp_slash_commands = "\\",
      editor_context = "#",
      slash_commands = "/",
      tools = "@",
    },
  },
})
```

## Callbacks

Callbacks allow you to hook into the chat buffer's lifecycle and react to specific events. They are registered per-chat and receive the chat instance as the first argument.

### Available Events

| Event | Description | Extra Args |
|---|---|---|
| `on_created` | Chat buffer has been created | - |
| `on_before_submit` | Before the message is sent to the LLM. Return `false` to prevent submission | `{ adapter }` |
| `on_submitted` | After the message has been sent to the LLM | `{ payload }` |
| `on_ready` | Chat is ready for the next turn (after LLM response) | - |
| `on_completed` | LLM response has been fully processed | `{ status }` |
| `on_cancelled` | Request has been stopped/cancelled | - |
| `on_closed` | Chat buffer has been closed | - |

### Registering Callbacks

Callbacks can be registered in two ways:

::: code-group

```lua [All Chats]
vim.api.nvim_create_autocmd("User", {
  pattern = "CodeCompanionChatCreated",
  callback = function(args)
    local chat = require("codecompanion").buf_get_chat(args.data.bufnr)
    chat:add_callback("on_before_submit", function(c, info)
      -- Access the adapter via info.adapter
      -- Access messages via c.messages
    end)
  end,
})
```

```lua [Prompt Library]
require("codecompanion").setup({
  prompt_library = {
    ["My Prompt"] = {
      opts = {
        callbacks = {
          on_before_submit = function(chat, info)
            -- Only applies to chats opened from this prompt
          end,
        },
      },
    },
  },
})
```

:::

### Background Callbacks

Callbacks can also be registered in the config via `interactions.background.chat.callbacks`. These run asynchronously using a separate background LLM instance and are suited for fire-and-forget tasks like generating chat titles. Unlike the callbacks above, they cannot return values to influence the chat's behavior:

```lua
require("codecompanion").setup({
  interactions = {
    background = {
      chat = {
        callbacks = {
          ["on_ready"] = {
            actions = {
              "interactions.background.builtin.chat_make_title",
            },
            enabled = true,
          },
        },
        opts = {
          enabled = true,
        },
      },
    },
  },
})
```

The `actions` table contains module paths that are resolved and executed asynchronously. See the [generating titles](/usage/chat-buffer/#generating-titles) section for a working example.

### Preventing Submission

The `on_before_submit` callback can return `false` to prevent a message from being sent to the LLM. When cancelled, `chat:restore()` is called automatically, which resets the buffer to an editable state and fires a `CodeCompanionChatRestored` event. The user's message remains in the buffer so it can be edited and resubmitted.

This is useful for implementing safeguards such as token/context limit checks:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "CodeCompanionChatCreated",
  callback = function(args)
    local chat = require("codecompanion").buf_get_chat(args.data.bufnr)
    chat:add_callback("on_before_submit", function(c, data)
      local token_count = my_tokenizer.count(c.messages)
      local context_limit = 128000

      if token_count > context_limit then
        vim.notify(
          string.format("Token count (%d) exceeds context limit (%d)", token_count, context_limit),
          vim.log.levels.WARN
        )
        return false
      end
    end)
  end,
})
```

The `info` table passed to `on_before_submit` contains:

- `adapter` - A safe copy of the current adapter (with name, model, features, schema, etc.)

## Diff

<img src="https://github.com/user-attachments/assets/8d80ed10-12f2-4c0b-915f-63b70797a6ca" alt="Diff"/>

CodeCompanion has a built-in diff engine that's leveraged throughout the plugin. If you utilize the `insert_edit_into_file` tool or use an ACP adapter, then the plugin will update files and buffers, displaying the changes in a floating window.

There are a number of configuration option available to you:

::: code-group

```lua [Display]
require("codecompanion").setup({
  display = {
    diff = {
      enabled = true,
      word_highlights = {
        additions = true,
        deletions = true,
      },
    },
  },
})
```

```lua [Window Opts] {5-17}
require("codecompanion").setup({
  display = {
    diff = {
      enabled = true,
      window = {
        ---@return number|fun(): number
        width = function()
          return math.min(120, vim.o.columns - 10)
        end,
        ---@return number|fun(): number
        height = function()
          return vim.o.lines - 4
        end,
        opts = {
          number = true,
        },
      },
      word_highlights = {
        additions = true,
        deletions = true,
      },
    },
  },
})
```

:::

## Keymaps

> [!NOTE]
> The plugin scopes CodeCompanion specific keymaps to the _chat buffer_ only.

You can define or override the [default keymaps](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua#L178) to send messages, regenerate responses, close the buffer, etc.

::: code-group

```lua [Chat] {3}
require("codecompanion").setup({
  interactions = {
    chat = {
      keymaps = {
        send = {
          modes = { n = "<C-s>", i = "<C-s>" },
          opts = {},
        },
        close = {
          modes = { n = "<C-c>", i = "<C-c>" },
          opts = {},
        },
        -- Change further custom keymaps here
        -- ...
        -- Set a keymap to be false to disable it
        some_other_keymap = false,
      },
    },
  },
})
```

```lua [Inline] {3}
require("codecompanion").setup({
  interactions = {
    inline = {
      keymaps = {
        stop = {
          callback = "keymaps.stop",
          description = "Stop request",
          modes = { n = "q" },
        },
      },
    },
  },
})
```

```lua [Diff] {3}
require("codecompanion").setup({
  interactions = {
    shared = {
      keymaps = {
        always_accept = {
          callback = "keymaps.always_accept",
          modes = { n = "g1" },
        },
        accept_change = {
          callback = "keymaps.accept_change",
          modes = { n = "g2" },
        },
        reject_change = {
          callback = "keymaps.reject_change",
          modes = { n = "g3" },
        },
        next_hunk = {
          callback = "keymaps.next_hunk",
          modes = { n = "}" },
        },
        previous_hunk = {
          callback = "keymaps.previous_hunk",
          modes = { n = "{" },
        },
      },
    },
  },
})
```

:::

For the chat interaction, the keymaps are mapped to `<C-s>` for sending a message and `<C-c>` for closing in both normal and insert modes. To set other `:map-arguments`, you can use the optional `opts` table which will be fed to `vim.keymap.set`.

## Prompt Decorator

It can be useful to decorate your prompt with additional information, prior to sending to an LLM. For example, the GitHub Copilot prompt in VS Code, wraps a user's prompt between `<prompt></prompt>` tags, presumably to differentiate the user's ask from additional context. This can also be achieved in CodeCompanion:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      opts = {
        ---Decorate the user message before it's sent to the LLM
        ---@param message string
        ---@param adapter CodeCompanion.Adapter
        ---@param context table
        ---@return string
        prompt_decorator = function(message, adapter, context)
          return string.format([[<prompt>%s</prompt>]], message)
        end,
      }
    }
  }
})
```

The decorator function also has access to the adapter in the chat buffer alongside the [context](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/utils/context.lua#L121-L137) table (which refreshes when a user toggles the chat buffer).

## Slash Commands

> [!IMPORTANT]
> Each slash command may have their own unique configuration so be sure to check out the [config.lua](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua) file

[Slash Commands](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua#L114) (invoked with `/` by default) let you dynamically insert context into the chat buffer, such as file contents or date/time.

The plugin supports providers like [telescope](https://github.com/nvim-telescope/telescope.nvim), [mini_pick](https://github.com/echasnovski/mini.pick), [fzf_lua](https://github.com/ibhagwan/fzf-lua) and [snacks.nvim](https://github.com/folke/snacks.nvim). By default, the plugin will automatically detect if you have any of those plugins installed and duly set them as the default provider. Failing that, the in-built `default` provider will be used. Please see the [Chat Buffer](/usage/chat-buffer/index) usage section for information on how to use Slash Commands.

::: code-group

```lua [Configure]
require("codecompanion").setup({
  interactions = {
    chat = {
      slash_commands = {
        ["file"] = {
          -- Use Telescope as the provider for the /file command
          opts = {
            provider = "telescope", -- Can be "default", "telescope", "fzf_lua", "mini_pick" or "snacks"
          },
        },
      },
    },
  },
})
```

```lua [Keymaps]
require("codecompanion").setup({
  interactions = {
    chat = {
      slash_commands = {
        ["file"] = {
          keymaps = {
            modes = {
              i = "<C-f>",
              n = { "<C-f>", "gf" },
            },
          },
        },
      },
    },
  },
})
```

```lua [Conditionally Enable]
require("codecompanion").setup({
  interactions = {
    chat = {
      slash_commands = {
        ["image"] = {
          ---@param opts { adapter: CodeCompanion.HTTPAdapter }
          ---@return boolean
          enabled = function(opts)
            return opts.adapter.opts and opts.adapter.opts.vision == true
          end,
        },
      },
    },
  },
})
```

```lua [Custom Commands]
require("codecompanion").setup({
  interactions = {
    chat = {
      slash_commands = {
        ["git_files"] = {
          description = "List git files",
          ---@param chat CodeCompanion.Chat
          callback = function(chat)
            local handle = io.popen("git ls-files")
            if handle ~= nil then
              local result = handle:read("*a")
              handle:close()
              chat:add_context({ role = "user", content = result }, "git", "<git_files>")
            else
              return vim.notify("No git files available", vim.log.levels.INFO, { title = "CodeCompanion" })
            end
          end,
          opts = {
            contains_code = false,
          },
        },
      },
    },
  },
})
```

:::

Credit to [@lazymaniac](https://github.com/lazymaniac) for the [inspiration](https://github.com/olimorris/codecompanion.nvim/discussions/958) for the custom slash command example.

## Tools

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
            },
          },
        },
      },
    },
  },
})
```

When users introduce the group, `my_group`, in the chat buffer, it can call the tools you listed (such as `run_command`) to perform tasks on your code.

A tool is a [`CodeCompanion.Tool`](/extending/tools) table with specific keys that define the interface and workflow of the tool. The table can be resolved using the `callback` option. The `callback` option can be a table itself or either a function or a string that points to a luafile that return the table.

### Enabling Tools

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

### Approvals

CodeCompanion allows you to apply safety mechanisms to its built-in tools prior to execution. See the [approvals usage](/usage/chat-buffer/tools#approvals) section for more information.

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

### Auto Submit (Recursion)

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

### Default Tools

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

## User Interface (UI)

> [!NOTE]
> The [other plugins](/installation#other-plugins) section contains installation instructions for some popular markdown rendering plugins

### Auto Scrolling

By default, the page scrolls down automatically as the response streams, with the cursor placed at the end. This can be distracting if you are focusing on the earlier content while the page scrolls up away during a long response. You can disable this behavior using a flag:

```lua
require("codecompanion").setup({
  display = {
    chat = {
      auto_scroll = false,
    },
  },
})
```

> [!TIP]
> If you move your cursor while the LLM is streaming a response, auto-scrolling will be turn off.

### Completion

By default, CodeCompanion looks to use the fantastic [blink.cmp](https://github.com/Saghen/blink.cmp) plugin to complete editor context, slash commands and tools. However, you can override this in your config:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      opts = {
        completion_provider = "cmp", -- blink|cmp|coc|default
      }
    }
  }
})
```

The plugin also supports [nvim-cmp](https://github.com/hrsh7th/nvim-cmp), a native completion solution (`default`), and [coc.nvim](https://github.com/neoclide/coc.nvim).



### Context

It's not uncommon for users to share many items, as context, with an LLM. This can impact the chat buffer's UI significantly, leaving a large space between the LLM's last response and the user's input. To minimize this impact, the context can be folded:

```lua
require("codecompanion").setup({
  display = {
    chat = {
      icons = {
        chat_context = "📎️", -- You can also apply an icon to the fold
      },
      fold_context = true,
    },
  },
})
```

### Layout

The plugin leverages floating windows to display content to a user in a variety of scenarios, such as with the [debug window](/usage/chat-buffer/#messages) or agent [permissions](/usage/chat-buffer/agents.html#permissions). You can change the appearance of the chat buffer by changing the `display.chat.window` table in your configuration.

::: code-group

```lua [Icons]
require("codecompanion").setup({
  display = {
    chat = {
      -- Change the default icons
      icons = {
        buffer_sync_all = "󰪴 ",
        buffer_sync_diff = " ",
        chat_context = " ",
        chat_fold = " ",
        tool_pending = "  ",
        tool_in_progress = "  ",
        tool_failure = "  ",
        tool_success = "  ",
      },
    },
  },
})
```

```lua [Chat Buffer]
require("codecompanion").setup({
  display = {
    chat = {
      window = {
        buflisted = false, -- List the chat buffer in the buffer list?
        sticky = false, -- Chat buffer remains open when switching tabs

        layout = "vertical", -- float|vertical|horizontal|tab|buffer
        full_height = true, -- for vertical layout
        position = nil, -- left|right|top|bottom (nil will default depending on vim.opt.splitright|vim.opt.splitbelow)

        width = 0.5, ---@return number|fun(): number
        height = 0.8, ---@return number|fun(): number
        border = "single",
        relative = "editor",

        -- Ensure that long paragraphs of markdown are wrapped
        opts = {
          breakindent = true,
          linebreak = true,
          wrap = true,
        },
      },
    },
  },
})
```

```lua [Floating Window]
require("codecompanion").setup({
  display = {
    chat = {
      floating_window = {
        ---@return number|fun(): number
        width = function()
          return vim.o.columns - 5
        end,
        ---@return number|fun(): number
        height = function()
          return vim.o.lines - 2
        end,
        row = "center",
        col = "center",
        relative = "editor",
        opts = {
          wrap = false,
          number = false,
          relativenumber = false,
        },
      },
    },
  },
})
```

:::

### Reasoning

An adapter's reasoning is streamed into the chat buffer by default, under a `h3` heading. By default, this output will be folded once streaming has been completed. You can turn off folding and hide reasoning output altogether:

```lua
require("codecompanion").setup({
  display = {
    chat = {
      icons = {
        chat_fold = " ",
      },
      fold_reasoning = false,
      show_reasoning = false,
    },
  },
})
```

### Roles

The chat buffer places user and LLM responses under a `H2` header. These can be customized in the configuration:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      roles = {
        ---The header name for the LLM's messages
        ---@type string|fun(adapter: CodeCompanion.Adapter): string
        llm = function(adapter)
          return "CodeCompanion (" .. adapter.formatted_name .. ")"
        end,

        ---The header name for your messages
        ---@type string
        user = "Me",
      }
    }
  }
})
```

By default, the LLM's responses will be placed under a header such as `CodeCompanion (DeepSeek)`, leveraging the current adapter in the chat buffer. This option can be in the form of a string or a function that returns a string. If you opt for a function, the first parameter will always be the adapter from the chat buffer.

The user role is currently only available as a string.

### Others

There are also a number of other options that you can customize in the UI:

```lua
require("codecompanion").setup({
  display = {
    chat = {
      intro_message = "Welcome to CodeCompanion ✨! Press ? for options",
      separator = "─", -- The separator between the different messages in the chat buffer
      show_context = true, -- Show context (from editor context and slash commands) in the chat buffer?
      show_header_separator = false, -- Show header separators in the chat buffer? Set this to false if you're using an external markdown formatting plugin
      show_settings = false, -- Show LLM settings at the top of the chat buffer?
      show_token_count = true, -- Show the token count for each response?
      show_tools_processing = true, -- Show the loading message when tools are being executed?
      start_in_insert_mode = false, -- Open the chat buffer in insert mode?
    },
  },
})
```


## Editor Context

[Editor context](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua#L90) can be  a inserted into the chat buffer using `#` (by default). It provides contextual code or information about the current Neovim state. For instance, the built-in `#{buffer}` editor context sends the current buffer’s contents to the LLM.

You can even define your own context:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      editor_context = {
        ["my_editor_context_item"] = {
          ---Ensure the file matches the CodeCompanion.EditorContext class
          ---@return string|fun(): nil
          callback = "/Users/Oli/Code/my_editor_context_item.lua",
          description = "Explain what your does",
          opts = {
            contains_code = false,
            --has_params = true,    -- Set this if your editor context item supports parameters
            --default_params = nil, -- Set default parameters
          },
        },
      },
    },
  },
})
```

### Syncing

Neovim buffers can be [synced](/usage/chat-buffer/editor-context#with-parameters) with the chat buffer. That is, on each turn their content can be shared with the LLM. This is useful if you're modifying a buffer and want the LLM to always have the latest changes.

To enable this by default for the built-in `#buffer` editor context, you can set the `default_params` option to either `diff` or `all`:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      editor_context = {
        ["buffer"] = {
          opts = {
            -- Always sync the buffer by sharing its "diff"
            -- Or choose "all" to share the entire buffer
            default_params = "diff",
          },
        },
      },
    },
  },
})
```






