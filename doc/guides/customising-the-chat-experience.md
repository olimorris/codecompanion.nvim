---
description: "Shape CodeCompanion's chat buffer around how you work, from where it opens to where you write and how you follow a response."
---

# Customising the Chat Experience

CodeCompanion's chat buffer opens beside your code and takes your message at the bottom of the conversation. That suits most people, but you can move it, write in a separate split and keep working whilst a response streams. Each section below starts with the situation it suits. For every option, see [Configuring the Chat Buffer UI](/configuration/ui).

## Where the Chat Opens

The chat opens in a vertical split by default. Choose a layout under `display.chat.window` to suit your screen:

| Layout | Suits |
|---|---|
| `vertical` | A wide screen, with code and chat side by side |
| `horizontal` | A narrow or portrait screen, with the chat above or below your code |
| `float` | Dipping in for a quick question, then hiding it again |
| `tab` | Long conversations that deserve the whole screen |
| `buffer` | Treating the chat like any other buffer in the current window |

To open the chat in a split beneath your code:

```lua
require("codecompanion").setup({
  display = {
    chat = {
      window = {
        layout = "horizontal", -- Can be "float", "vertical", "horizontal", "tab" or "buffer"
        position = "bottom", -- Can be "left", "right", "top" or "bottom"
        height = 0.4,
      },
    },
  },
})
```

If you work across several tabs, `pertab = true` gives each tab its own chat window, whilst `sticky = true` moves the one chat window with you as you switch tabs. With the `vertical` layout, `full_height = false` splits only the current window rather than the whole height of the editor. See [Layout](/configuration/ui#layout) for the full list of options.

<img src="https://github.com/user-attachments/assets/1aa046dd-1102-4663-aad3-0d792a5a5ecd" alt="Chat in a horizontal split beneath the code" />

## Writing Your Message

By default, you write your message at the bottom of the chat buffer, beneath the conversation. That's the simplest setup, but your message shares a buffer with a response that's still streaming in.

If you'd rather keep what you're writing apart from the conversation, write it in a separate split beneath the chat window:

```lua
require("codecompanion").setup({
  display = {
    chat = {
      input = {
        layout = "split", -- Can be "buffer" or "split"
        height = 8, -- lines
      },
    },
  },
})
```

When you send it, your message is added to the chat buffer under your header. With the split:

- **Chat buffer** - It's read-only, and the chat settings from `display.chat.show_settings` aren't shown at the top
- **Filetype** - The input is a `codecompanion_chat_input` buffer, so it can be targeted separately from the chat buffer in your statusline or autocmds
- **Keymaps** - Every chat buffer keymap works in both windows. Pressing `i`, `a`, `I`, `A`, `o` or `O` in the chat buffer moves you to the input
- **Window** - Hiding or closing either window closes both. If you resize the input, that chat keeps the new height until you restart Neovim. New chats open at `height`

<img src="https://github.com/user-attachments/assets/6618a50b-da5d-43a9-8552-fec656a29f06" alt="Input split beneath the chat window" />

## Working Whilst It Streams

A long response or a run of tool calls can take a while, and you may think of your next message before it finishes.

With the split, write and send it as normal. **A message sent whilst the LLM is responding is queued**, then sent once it's safe to do so. Sending another adds it to the same queued message. Stopping the response moves the queued message back into the input, above anything you're writing.

With the default layout, press `gm` whilst the LLM is responding to send a follow-up, which CodeCompanion delivers in the same way. See [Using the Chat Buffer](/usage/chat-buffer/).

## Moving Through a Conversation

The chat buffer follows the response as it streams in. Move the cursor away to read something earlier and it stops following, and moving back to the bottom starts it again. To turn this off:

```lua
require("codecompanion").setup({
  display = {
    chat = {
      auto_scroll = false,
    },
  },
})
```

`[[` and `]]` move between messages in the chat buffer, even when pressed in the input.

With the split, the input also has keymaps to scroll the chat buffer without leaving it, in normal and insert mode:

| Keymap | Name | Description |
|---|---|---|
| `<M-j>` | `scroll_chat_down` | Scroll the chat down half a page |
| `<M-k>` | `scroll_chat_up` | Scroll the chat up half a page |
| `<M-g>` | `scroll_chat_jump` | Jump to the bottom of the chat, or to the top if you're already at the bottom |

Scrolling up stops the chat following the response, and jumping back to the bottom starts it again. To change these keymaps, see [Keymaps](/configuration/chat-buffer#keymaps).

## Context

Context you share, such as a buffer or a file, is listed in a block above your message.

With the default layout, the block sits under your header in the chat buffer. If a lot of context pushes your message too far from the last response, fold it into a single line with `display.chat.fold_context = true`. See [Context](/configuration/ui#context).

With the split, the block sits at the top of the input and stays there between messages. `fold_context` folds the items there too, leaving the header visible. Delete a line to remove that item from the chat.

<img src="https://github.com/user-attachments/assets/c6078047-13e5-4399-9e4f-1c9a18e21be3" alt="Context block at the top of the input" />

## Limitations

- The input split isn't available for the `float` layout, which keeps writing at the bottom of the chat buffer
- On macOS, your terminal must send the Option key as Meta for `<M-j>`, `<M-k>` and `<M-g>` to reach Neovim
