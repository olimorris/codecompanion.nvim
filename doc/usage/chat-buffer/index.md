---
description: "Converse with an LLM or an agent in a Neovim buffer, sharing context and switching adapters as you go."
prev:
  text: 'Action Palette'
  link: '/usage/action-palette'
next:
  text: 'Agents and Tools'
  link: '/usage/chat-buffer/agents-tools'
---

# Using the Chat Buffer

The _chat buffer_ is where you converse with an LLM or an agent. It's a markdown buffer, with a filetype of `codecompanion`, where `H2` headers separate your messages from the LLM's responses.

To open a chat buffer:

```
:CodeCompanionChat
```

To show or hide it:

```
:CodeCompanionChat Toggle
```

The Lua equivalents, `require("codecompanion").chat()` and `require("codecompanion").toggle()`, also accept window options:

```lua
require("codecompanion").chat({ window_opts = { layout = "float", width = 0.6 } })
```

Press `<CR>` or `<C-s>` in normal mode, or `<C-s>` in insert mode, to send your message. The response streams back into the buffer. While the LLM is running tools, press `gm` to send it a follow-up, which CodeCompanion delivers once it's safe to do so.

## Action Palette

From a chat buffer, `:CodeCompanionActions` opens the chat's own [Action Palette](/usage/action-palette), listing its keymaps and slash commands.

## Changing Adapter and Model

<img src="https://github.com/user-attachments/assets/e19ade4f-1daa-4634-b071-4ecd400371eb" alt="Change adapter and model" />

Press `ga` to pick a different adapter. If the adapter has more than one model, you're asked to pick one of those too. This works for both HTTP and ACP adapters, so you can move between an LLM and an agent in the same chat.

## Changing ACP Command

ACP adapters start the agent with a command from your configuration, `default` unless you choose otherwise. To start one with a different command:

```
:CodeCompanionChat adapter=gemini_cli command=yolo
```

From inside a chat buffer, use the [/command](/usage/chat-buffer/slash-commands#command) slash command.

## Completion

<img src="https://github.com/user-attachments/assets/02b4d5e2-3b40-4044-8a85-ccd6dfa6d271" alt="Completion" />

Type a trigger character to open the completion menu:

| Trigger | Completes |
| --- | --- |
| `#` | [Editor context](/usage/chat-buffer/editor-context), such as `#{buffer}` |
| `@` | [Tools](/usage/chat-buffer/agents-tools), such as `@{agent}` |
| `/` | [Slash commands](/usage/chat-buffer/slash-commands) |
| `\` | Commands from an ACP agent, such as `\compact` |

Completion works with blink.cmp, nvim-cmp and coc.nvim. Without a completion plugin, press `<C-_>` for native completion. The trigger characters can be changed under `opts.triggers`.

ACP commands come from the agent itself, and CodeCompanion turns `\command` into `/command` when you send the message. The backslash keeps them apart from CodeCompanion's own slash commands.

> [!NOTE]
> ACP commands take a few seconds to appear after you open a chat buffer, and only the commands an agent exposes through its SDK are listed

## Context

<img src="https://github.com/user-attachments/assets/e8a31214-ccba-407f-a8e4-32ba185a3ecd" alt="context" />

Add context with [editor context](/usage/chat-buffer/editor-context), [slash commands](/usage/chat-buffer/slash-commands) and [tools](/usage/chat-buffer/agents-tools). Each item is listed in a `Context` blockquote at the top of your message.

> [!IMPORTANT]
> A context item is a snapshot of its source at the time it was added. Only `#{buffer}` and `#{buffers}` stay in sync by default

To keep any other buffer or file up to date, sync it to the chat buffer. Put your cursor on the context item and press:

- `gba` to send its entire content on every turn
- `gbd` to send only what's changed since the last turn

Sending the entire content means the LLM always sees the latest version, at the cost of more tokens. Sending the diff is cheaper.

Some file types are worth syncing as soon as they're added. Jupyter Notebooks change on disk every time a cell runs, so they're synced by default. To add more, see [Syncing](/configuration/chat-buffer#syncing).

HTTP adapters send the whole conversation on every turn, so the LLM can refer to context you shared many messages ago. To change that history, use the [debug window](#debug-window).

### Adding via Paths

To attach a file or URL, write it as a [markdown link](https://www.markdownguide.org/basic-syntax/#links):

```markdown
I want to share [File](~/Code/Neovim/codecompanion.nvim/README.md) with you
```

When you send the message, the file is attached and the link is replaced with its path. This works for text files, images and PDFs. URLs are fetched with the [fetch](/usage/chat-buffer/slash-commands#fetch) slash command's adapter, without a cache.

Markdown can't parse a bare space in a link, so wrap a path that contains one:

| Link | Attached |
| --- | --- |
| `[File](/Users/Oli/Downloads/report.txt)` | Yes |
| `[File](</Users/Oli/Downloads/some report.txt>)` | Yes |
| `[File]('/Users/Oli/Downloads/some report.txt')` | Yes |
| `[File]("/Users/Oli/Downloads/some report.txt")` | Yes |
| `[File](/Users/Oli/Downloads/some report.txt)` | No |

### Removing

To remove a context item, delete its line from the `Context` blockquote. On the next turn, everything it added is removed from the message history.

## Debug Window

<img src="https://github.com/user-attachments/assets/9790def5-dc9c-4922-911f-90c6042b122d" alt="Debug window" />

Press `gd` to open the _debug window_. It shows what's sent to the LLM on the next turn: the adapter's settings, the context items and the full message history, including the system prompt and other messages hidden from the chat buffer.

The debug window is a Lua buffer. Edit it, then press `<C-s>` to write your changes back to the chat buffer.

## Generating Titles

CodeCompanion can give each chat buffer a title, written by a [background interaction](/guides/background-model). To turn it on:

```lua
require("codecompanion").setup({
  interactions = {
    background = {
      chat = {
        opts = {
          enabled = true,
        },
      },
    },
  },
})
```

See [Chat Titles](/guides/background-model#chat-titles) to choose the model that writes them.

## Images

<p>
<video controls muted title="Adding images to the chat buffer" src="https://github.com/user-attachments/assets/8897d58e-f2c4-4da9-a170-22f31a75c358"></video>
</p>

Add images from disk with [/file](/usage/chat-buffer/slash-commands#file), from a URL with [/file-from-url](/usage/chat-buffer/slash-commands#file-from-url), or from the clipboard with [img-clip.nvim](/installation#img-clip-nvim). Both local and remote images are base64 encoded.

If the model doesn't accept images, CodeCompanion leaves them out of the request.

## Keymaps

Press `?` in a chat buffer to list every keymap. The defaults in normal mode are:

| Keymap | Name | Description |
| --- | --- | --- |
| `<CR>` `<C-s>` | `send` | Send the message to the LLM |
| `<C-c>` | `close` | Close the chat buffer |
| `q` | `stop` | Stop the current request |
| `ga` | `change_adapter` | Change adapter and model |
| `gba` | `sync_all` | Toggle live-syncing of a context item |
| `gbd` | `sync_diff` | Toggle diff-only syncing of a context item |
| `gc` | `codeblock` | Insert an empty codeblock |
| `gd` | `debug` | Open the debug window |
| `gf` | `fold_code` | Fold all codeblocks |
| `gm` | `_btw` | Send a follow-up while the LLM is running |
| `gM` | `rules` | Remove rules from the chat |
| `gr` | `regenerate` | Regenerate the last response |
| `gR` | `goto_file_under_cursor` | Open the file path under the cursor |
| `gs` | `system_prompt` | Toggle the system prompt on and off |
| `gS` | `copilot_stats` | Show Copilot usage statistics |
| `gtx` | `clear_approvals` | Reset cached tool approvals |
| `gty` | `yolo_mode` | Choose how tool calls are approved |
| `gx` | `clear` | Clear all messages from the chat |
| `gy` | `yank_code` | Yank code from the last codeblock |
| `}` `{` | `next_chat` `previous_chat` | Move to the next or previous chat |
| `]]` `[[` | `next_header` `previous_header` | Jump to the next or previous header |

In insert mode, `<C-s>` sends the message, `<C-c>` closes the chat buffer and `<C-_>` opens the completion menu. To change any of them, see [Keymaps](/configuration/chat-buffer#keymaps).

## Multiple Chats

Open as many chat buffers as you like. Cycle through them with `{` and `}`, and use `:CodeCompanionChat Toggle` to show or hide the last one.

By default, opening or cycling to a chat hides the one that's visible. To give each tab its own chat, so a chat in one tab is never closed or replaced from another:

```lua
require("codecompanion").setup({
  display = {
    chat = {
      window = {
        pertab = true,
      },
    },
  },
})
```

With `pertab` enabled, `{` and `}` only cycle through chats that are visible in the current tab or hidden everywhere, and `:CodeCompanionChat Toggle` jumps to the tab a chat lives in.

## Settings

<img src="https://github.com/user-attachments/assets/01f1e482-1f7b-474f-ae23-f25cc637f40a" alt="Settings" />

To tweak the model's settings between responses, show them as a YAML block at the top of the chat buffer:

```lua
require("codecompanion").setup({
  display = {
    chat = {
      show_settings = true,
    },
  },
})
```

The block mirrors the adapter's `schema` table. Edit a value and it's used from the next response onwards.
