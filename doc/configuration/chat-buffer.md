---
description: "Configure CodeCompanion's chat buffer in Neovim, covering the adapter, keymaps, editor context, slash commands and how attached content is shaped."
---

# Configuring the Chat Buffer

By default, CodeCompanion provides a _chat_ interaction that uses a dedicated Neovim buffer for conversational interaction with your chosen LLM. This buffer can be customized according to your preferences.

Please refer to the [config.lua](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua#L42-L392) file for a full list of all configuration options.

The chat buffer's larger areas of configuration have pages of their own:

- [Callbacks](/configuration/callbacks) - hooking into the chat buffer's lifecycle
- [Context Management](/configuration/context-management) - editing and compaction triggers
- [Sessions](/configuration/sessions) - saving chats to disk and resuming them
- [Tools](/configuration/tools) - tool groups, approvals and the LLM judge
- [UI](/configuration/ui) - window layout, icons, folding and roles

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

To disable a keymap, you can set it to `false` in your configuration:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      keymaps = {
        send = false,
        close = false
      }
    }
  }
})
```

## Editor Context

[Editor context](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua#L90) can be inserted into the chat buffer using `#` (by default). It provides contextual code or information about the current Neovim state. For instance, the built-in `#{buffer}` editor context sends the current buffer’s contents to the LLM.

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

For the built-in `#buffer` editor context, this is enabled by default. However, you can change it with:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      editor_context = {
        ["buffer"] = {
          opts = {
            -- Always sync the buffer by sharing its "diff"
            -- Or choose "all" to share the entire buffer
            default_params = "all",
          },
        },
      },
    },
  },
})
```

## Syncing Buffers/Files

[Context items](/usage/chat-buffer/#context) hold the data of a file or buffer at a point in time.

Depending on the file type, it may be worthwhile continuously syncing their content with an LLM. Extensions listed in `sync_diff` are watched from the moment they're added to the chat buffer, whether that's with `/file`, `/buffer`, `#{buffer}` or `#{buffers}`:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      opts = {
        sync_diff = {
          ipynb = true, -- Notebooks change on disk whenever a cell is run
          sqlite = true,
        },
      },
    },
  },
})
```

To change how a file's content is shaped before the LLM sees it, see [Context Formatters](/configuration/chat-buffer#context-formatters).

## Context Formatters

You can customise how a buffer and file's content is shared with an LLM with context formatters.

**Example:** A [Jupyter Notebook](https://jupyter.org/) is a large JSON document with markdown, code and sometimes base64 images embedded in it. They ca be large files which quickly erode an LLM's context window.

A context formatter modifies a file's content before it is shared with an LLM. This is the case whether the file was attached with `/file`, opened as a buffer and attached with `/buffer`, pulled in by a rules file, or re-read to produce a [sync](/configuration/chat-buffer#syncing) diff.

You can define your own formatter by ensuring your you implement a `format(raw, path)` function which returns the content the LLM should see, or the path to a module which returns one:

::: code-group

```lua [Function]
require("codecompanion").setup({
  context = {
    formatters = {
      sqlite = function(raw, path)
        -- Return the content the LLM should see for this file
      end,
    },
  },
})
```

```lua [Path]
require("codecompanion").setup({
  context = {
    formatters = {
      -- The path to any module, or file, which returns a table with a `format` function.
      sqlite = "my_plugin.context.formatters.sqlite",
    },
  },
})
```

:::

Formatters are responsible for their own formatting, so content they return is passed through as-is. Content they do not touch is wrapped in a code fence when attached to the chat, and buffers additionally get line numbers. Neither is applied when content is re-read for a sync diff, as the diff itself is fenced.

## Slash Commands

> [!IMPORTANT]
> Each slash command may have their own unique configuration so be sure to check out the [config.lua](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua) file

[Slash Commands](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua#L114) (invoked with `/` by default) let you dynamically insert context into the chat buffer, such as file contents or date/time.

The plugin supports providers like [telescope](https://github.com/nvim-telescope/telescope.nvim), [mini_pick](https://github.com/echasnovski/mini.pick), [fzf_lua](https://github.com/ibhagwan/fzf-lua) and [snacks.nvim](https://github.com/folke/snacks.nvim). By default, the plugin will automatically detect if you have any of those plugins installed and duly set them as the default provider. Failing that, the in-built `default` provider will be used. Please see the [Chat Buffer](/usage/chat-buffer/) usage section for information on how to use Slash Commands.

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

You can also customize the prefixes that trigger completions for [editor context](/usage/chat-buffer/editor-context), [slash commands](/usage/chat-buffer/slash-commands), and [tools](/usage/chat-buffer/agents-tools):

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
