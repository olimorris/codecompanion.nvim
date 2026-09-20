---
description: "Save CodeCompanion chats to disk in Neovim and resume them later, with autosave, continuous save and a configurable save directory."
---

# Configuring Sessions

A session is a chat saved to disk that can be resumed at a later point in time. Sessions can be configured with `sessions`:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      sessions = {
        enabled = true,
        autosave = true,
        continuous_save = true,
        save_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "codecompanion", "sessions"),
      },
    },
  },
})
```

`autosave` decides whether a chat *becomes* a session, and `continuous_save` decides whether a session is *continuously updated*. The [/save](/usage/chat-buffer/slash-commands#save) command can be used to manually save a session:


| `autosave` | `continuous_save` | Behaviour |
|------------|-------------------|-----------|
| `true` | `true` | Every chat is saved once the LLM has responded, and is continuously updated |
| `true` | `false` | Every chat is saved initially but not updated until the user triggers `/save` |
| `false` | `true` | Nothing is saved until the user triggers `/save`, after which it is continuously updated |
| `false` | `false` | Nothing is saved until the user triggers `/save`, and each `/save` is a snapshot |


An autosaved chat is named based on the user's opening message. If the [chat_make_title](/configuration/callbacks#background-callbacks) background callback is enabled, the LLM's title is used instead.

Setting `enabled = false` removes `/save`, the session list in `/resume` and the action palette entry.

Sessions can be restored with `/resume` the chat, from the action palette, or with:

```lua
require("codecompanion").sessions()
```
