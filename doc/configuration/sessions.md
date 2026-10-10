---
description: "Save chats to disk and resume them later, choosing when they're saved and where."
---

# Configuring Sessions

A _session_ is a chat saved to disk, which you can resume later. Sessions are configured under `interactions.chat.sessions`. To save every chat automatically:

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

`autosave` is `false` by default. Every other value above is the default.

## Saving

`autosave` decides whether a chat becomes a session on its own, and `continuous_save` decides whether a session keeps being updated. The [/save](/usage/chat-buffer/slash-commands#save) slash command saves a chat by hand:

| `autosave` | `continuous_save` | Behaviour |
| --- | --- | --- |
| `true` | `true` | Every chat is saved once the LLM responds, then after every response and on close |
| `true` | `false` | Every chat is saved once the LLM responds, then only on `/save` |
| `false` | `true` | Nothing is saved until `/save`, then after every response and on close |
| `false` | `false` | Nothing is saved until `/save`, and each `/save` is a snapshot |

An autosaved chat is named after your opening message. If the chat has a title, such as one from the [chat_make_title](/configuration/callbacks#background-callbacks) background callback, the title is used instead.

## Resuming

Resume a session with the [/resume](/usage/chat-buffer/slash-commands#resume) slash command, from the [action palette](/usage/action-palette), or with:

```lua
require("codecompanion").sessions()
```

## Disabling

Setting `enabled = false` removes `/save`, the session list in `/resume` and the action palette entry.

## Limitations

- Only chats with an HTTP adapter can be saved. ACP agents list their own sessions in `/resume`
