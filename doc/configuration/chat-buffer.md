---
description: "Set the chat buffer's adapter, completion, keymaps, editor context, slash commands and syncing."
---

# Configuring the Chat Buffer

The _chat buffer_ is where you converse with an LLM or an agent. Its settings live under `interactions.chat`, and every option is listed in [config.lua](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua).

## Changing Adapter

The chat buffer uses the `copilot` adapter by default. To use another HTTP or ACP adapter:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      adapter = {
        name = "anthropic",
        model = "claude-haiku-4-5-20251001",
      },
    },
  },
})
```

See [ACP adapters](/configuration/adapters-acp) and [HTTP adapters](/configuration/adapters-http) for the full list.

## Completion

CodeCompanion uses [blink.cmp](https://github.com/saghen/blink.cmp), [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) or [coc.nvim](https://github.com/neoclide/coc.nvim), in that order, if one is installed. Otherwise, it falls back to Neovim's native completion. You can override this with:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      opts = {
        completion_provider = "blink", -- Can be "blink", "cmp", "coc" or "default"
      },
    },
  },
})
```

### Triggers

The characters that open completion for [editor context](/usage/chat-buffer/editor-context), [slash commands](/usage/chat-buffer/slash-commands), [tools](/usage/chat-buffer/agents-tools) and ACP commands can be changed with:

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

## Context Formatters

Some files are a poor fit for an LLM as they are. A [Jupyter Notebook](https://jupyter.org/) is a large JSON document with markdown, code and base64 images embedded in it, which fills the context window quickly. A _context formatter_ changes a file's content before the LLM sees it.

Formatters are keyed by file extension, and apply whether the file is added with `/file`, `/buffer`, editor context, a rules file or a [sync](#syncing). CodeCompanion ships one for `ipynb` files.

A formatter is a function that takes the raw content and the path, and returns the content the LLM should see. It can also be the path to a module that returns a table with a `format` function:

::: code-group

```lua [Function]
require("codecompanion").setup({
  context = {
    formatters = {
      sqlite = function(raw, path)
        return vim.fn.system({ "sqlite3", path, ".schema" })
      end,
    },
  },
})
```

```lua [Module]
require("codecompanion").setup({
  context = {
    formatters = {
      sqlite = "my_plugin.context.formatters.sqlite",
    },
  },
})
```

:::

CodeCompanion passes a formatter's output through as it is. Content without a formatter is wrapped in a code block, and buffers also get line numbers. Neither applies to a sync diff, which is already fenced. If a formatter errors or doesn't return a string, the raw content is used instead.

## Editor Context

[Editor context](/usage/chat-buffer/editor-context), such as `#{buffer}`, shares part of your Neovim session with the LLM. It's configured under `interactions.shared.editor_context`, as it's shared with the [CLI interaction](/usage/cli).

To add your own, give it a `callback` that returns the content to send:

```lua
require("codecompanion").setup({
  interactions = {
    shared = {
      editor_context = {
        ["git_branch"] = {
          description = "Share the current git branch",
          callback = function()
            return "The current git branch is " .. vim.fn.system("git branch --show-current")
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

For more control, swap `callback` for `path`, pointing to a module built like those in `lua/codecompanion/interactions/shared/editor_context/`.

## Keymaps

Keymaps only apply to the chat buffer. You can change any of the [defaults](/usage/chat-buffer/#keymaps), and set `opts` to pass extra `:map-arguments` to `vim.keymap.set`:

::: code-group

```lua [Chat]
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

```lua [Inline]
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

```lua [Diff]
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

The keymaps under `interactions.shared` apply to diffs and tool approvals in both the chat buffer and the inline interaction. They also include `view_diff` (`gv`) and `cancel` (`g4`).

To disable a keymap, set it to `false`:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      keymaps = {
        send = false,
        close = false,
      },
    },
  },
})
```

## Prompt Decorator

A _prompt decorator_ changes your message before it's sent to the LLM. The GitHub Copilot prompt in VS Code, for example, wraps the user's message in `<prompt></prompt>` tags to separate it from the rest of the context. To do the same:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      opts = {
        ---@param message string
        ---@param adapter CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter
        ---@param context CodeCompanion.BufferContext
        ---@return string
        prompt_decorator = function(message, adapter, context)
          return string.format([[<prompt>%s</prompt>]], message)
        end,
      },
    },
  },
})
```

The `adapter` is a copy of the chat buffer's adapter, and `context` describes the buffer the chat was opened from. It's refreshed each time you toggle the chat buffer. Regenerating a response skips the decorator.

## Slash Commands

[Slash commands](/usage/chat-buffer/slash-commands) add context to the chat buffer, such as a file's contents or the date. Each has its own options, so check [config.lua](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua) for the full list.

Commands that open a picker use the first of Telescope, fzf-lua, mini.pick or Snacks that's installed. Otherwise, they fall back to a built-in `default` picker.

::: code-group

```lua [Provider]
require("codecompanion").setup({
  interactions = {
    chat = {
      slash_commands = {
        ["file"] = {
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
        ["file-from-url"] = {
          ---@param opts { adapter: CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter }
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
              chat:add_context({ role = "user", content = result }, { source = "git", id = "<git_files>" })
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

## Syncing

A [context item](/usage/chat-buffer/#context) is a snapshot of a buffer or file at the time it was added. [Syncing](/usage/chat-buffer/editor-context#syncing) shares its latest content with the LLM on every turn, either in full or as a diff.

`#{buffer}` syncs by sending a diff. To send the whole buffer instead:

```lua
require("codecompanion").setup({
  interactions = {
    shared = {
      editor_context = {
        ["buffer"] = {
          opts = {
            default_params = "all", -- Can be "all" or "diff"
          },
        },
      },
    },
  },
})
```

Some file types are worth syncing as soon as they're added. Extensions listed in `sync_diff` are synced as a diff whether they're added with `/file`, `/buffer`, `#{buffer}` or `#{buffers}`:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      opts = {
        sync_diff = {
          ipynb = true,
          sqlite = true,
        },
      },
    },
  },
})
```

Jupyter Notebooks change on disk every time a cell runs, so `ipynb` is listed by default. To change how a file's content looks to the LLM, see [Context Formatters](#context-formatters).
