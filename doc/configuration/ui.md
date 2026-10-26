---
description: "Change the chat buffer's window layout, icons, folding, scrolling, headers and reasoning output."
---

# Configuring the Chat Buffer UI

The chat buffer's appearance is set under `display.chat`. For markdown rendering plugins that work well with it, see [Other Plugins](/installation#other-plugins).

## Auto Scrolling

The chat buffer scrolls as the response streams in, keeping the cursor at the end. To turn this off:

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
> Moving the cursor while a response streams stops the scrolling for the rest of that response

## Context

Sharing a lot of context can push your next message well below the LLM's last response. To fold the context into a single line:

```lua
require("codecompanion").setup({
  display = {
    chat = {
      fold_context = true,
      icons = {
        chat_context = "📎️",
      },
    },
  },
})
```

The `chat_context` icon is optional and appears at the start of the fold.

## Input

By default, you write your message at the bottom of the chat buffer. To write it in a separate split beneath the chat window instead:

```lua
require("codecompanion").setup({
  display = {
    chat = {
      input = {
        layout = "split", -- Can be "buffer" or "split"
        height = 8, -- lines
        title = "CodeCompanion.nvim",
      },
    },
  },
})
```

With the split, the chat buffer is read-only, so you can scroll through a response and write your next message whilst it streams:

- **Submitting** - Your message is added to the chat buffer under your header
- **Queueing** - A message sent whilst the LLM is responding is queued and delivered once it's safe to do so. Sending another adds it to the same message. Stopping the response moves the queued message back into the input
- **Context** - Shared context sits at the top of the input and stays there between messages. It's never folded. Delete a line to remove that item
- **Title** - The chat buffer opens with `title` as a heading, which is replaced by the chat's title once it has one
- **Filetype** - The input is a `codecompanion_chat_input` buffer, so it can be targeted separately from the chat buffer in your statusline or autocmds
- **Keymaps** - Every chat buffer keymap works in both windows. `[[` and `]]` move between messages in the chat buffer, even from the input. Pressing `i`, `a`, `I`, `A`, `o` or `O` in the chat buffer moves you to the input
- **Window** - Hiding or closing either window closes both. If you resize the input, that chat keeps the new height until you restart Neovim. New chats open at `height`

The input also has keymaps to scroll the chat buffer without leaving it, in normal and insert mode:

| Keymap | Name | Description |
| ------ | ---- | ----------- |
| `<M-j>` | `scroll_chat_down` | Scroll the chat down half a page |
| `<M-k>` | `scroll_chat_up` | Scroll the chat up half a page |
| `<M-g>` | `scroll_chat_top_or_bottom` | Jump to the bottom of the chat, or the top if already there |

Scrolling up stops the chat following the response, and jumping back to the bottom starts it again. To change these keymaps, see [Keymaps](/configuration/chat-buffer#keymaps).

> [!TIP]
> On macOS, your terminal must send the Option key as Meta for `<M-j>`, `<M-k>` and `<M-g>` to reach Neovim

> [!NOTE]
> The split isn't available for the `float` layout, and the chat settings aren't shown at the top of the chat buffer

## Layout

The `display.chat.window` table sets where the chat buffer opens. The `display.chat.floating_window` table sets the size of the floating windows CodeCompanion opens, such as the [debug window](/usage/chat-buffer/#debug-window) and the [diff](/configuration/diff):

::: code-group

```lua [Chat Buffer]
require("codecompanion").setup({
  display = {
    chat = {
      window = {
        buflisted = false, -- List the chat buffer in the buffer list
        sticky = false, -- Move the chat window with you when switching tabs. Ignored when `pertab` is true
        pertab = false, -- Give each tab its own chat window

        layout = "vertical", -- Can be "float", "vertical", "horizontal", "tab" or "buffer"
        full_height = true, -- For the vertical layout
        position = nil, -- Can be "left", "right", "top" or "bottom". Defaults from `splitright` and `splitbelow`

        width = 0.5, -- Can be a number or a function. 0 leaves it to Neovim
        height = 0.8, -- Can be a number or a function. 0 leaves it to Neovim

        border = "single",
        relative = "editor",

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

```lua [Icons]
require("codecompanion").setup({
  display = {
    chat = {
      icons = {
        sync_all = "󰪴 ",
        sync_diff = " ",
        chat_context = " ",
        chat_fold = " ",
        tool_pending = "  ",
        tool_in_progress = "  ",
        tool_failure = "  ",
        tool_success = "  ",
      },
    },
  },
})
```

:::

A `width` or `height` below 1 is a share of the editor's size. Floating windows are centred and use your `winborder` setting for their border.

## Reasoning

A model's reasoning streams into the chat buffer under a `### Reasoning` heading, and is folded once the response finishes. To leave it unfolded, or hide it:

```lua
require("codecompanion").setup({
  display = {
    chat = {
      fold_reasoning = false,
      show_reasoning = false,
      icons = {
        chat_fold = " ",
      },
    },
  },
})
```

The `chat_fold` icon appears on folded reasoning.

## Roles

Your messages and the LLM's responses each sit under an `H2` header. To change the header text:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      roles = {
        ---@type string|fun(adapter: CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter): string
        llm = function(adapter)
          return "CodeCompanion (" .. adapter.formatted_name .. ")"
        end,

        ---@type string
        user = "Me",
      },
    },
  },
})
```

By default, the LLM's header names the chat's adapter, such as `CodeCompanion (DeepSeek)`. `llm` can be a string, or a function that receives the adapter. `user` can only be a string.

## Others

The remaining options, with their defaults:

```lua
require("codecompanion").setup({
  display = {
    chat = {
      intro_message = "Welcome to CodeCompanion ✨! Press ? for options",
      separator = "─", -- Separates the messages in the chat buffer
      show_context = true, -- Show the context you've shared in the chat buffer
      show_header_separator = false, -- Turn off if you use a markdown rendering plugin
      show_settings = false, -- Show the model's settings at the top of the chat buffer
      show_token_count = true, -- Show the token count for each response
      start_in_insert_mode = false, -- Open the chat buffer in insert mode

      ---@param tokens number
      ---@param adapter CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter
      ---@return string
      token_count = function(tokens, adapter)
        return " (" .. tokens .. " tokens)"
      end,
    },
  },
})
```
