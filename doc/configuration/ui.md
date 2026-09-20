---
description: "Customise the CodeCompanion chat buffer's appearance in Neovim, covering window layout, icons, folding, auto scrolling, roles and reasoning output."
---

# Configuring the Chat Buffer UI

> [!NOTE]
> The [other plugins](/installation#other-plugins) section contains installation instructions for some popular markdown rendering plugins

## Auto Scrolling

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

## Context

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

## Layout

The plugin leverages floating windows to display content to a user in a variety of scenarios, such as with the [debug window](/usage/chat-buffer/#messages). You can change the appearance of the chat buffer by changing the `display.chat.window` table in your configuration.

::: code-group

```lua [Icons]
require("codecompanion").setup({
  display = {
    chat = {
      -- Change the default icons
      icons = {
        sync_all = "󰪴 ",
        sync_diff = " ",
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
        sticky = false, -- Chat window follows when switching tabs (ignored when `pertab` is true)
        pertab = false, -- Treat each tab as having its own chat window?

        layout = "vertical", -- float|vertical|horizontal|tab|buffer
        full_height = true, -- for vertical layout
        position = nil, -- left|right|top|bottom (nil will default depending on vim.opt.splitright|vim.opt.splitbelow)

        -- NOTE: You can set these to 0 for auto width/height
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

## Reasoning

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

## Roles

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

## Others

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
      start_in_insert_mode = false, -- Open the chat buffer in insert mode?
    },
  },
})
```
