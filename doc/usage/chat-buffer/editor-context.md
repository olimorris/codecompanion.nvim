---
description: "Share buffers, diagnostics, git diffs, terminal output and other Neovim state with an LLM from the chat buffer."
---

# Using Editor Context

<p align="center">
  <img src="https://github.com/user-attachments/assets/642ef2df-f1c4-41c4-93e2-baa66d7f0801" alt="Using editor context" />
</p>

Editor context shares the state of Neovim with an LLM. Add `#{name}` to a message in the chat buffer, such as `#{buffer}`, and CodeCompanion adds the content when you send it. Type `#` to list everything available through completion.

| Editor context | Shares |
| --- | --- |
| `#{buffer}` | A buffer, kept in sync with the chat |
| `#{buffers}` | Every open buffer, kept in sync with the chat |
| `#{code_review}` | Your pending code review comments |
| `#{diagnostics}` | The diagnostics in a buffer, with the code they point at |
| `#{diff}` | The staged and unstaged git diff |
| `#{messages}` | Neovim's message history |
| `#{quickfix}` | The files in the quickfix list |
| `#{selection}` | Your current or most recent visual selection |
| `#{terminal}` | The latest output from a terminal buffer |
| `#{viewport}` | The code visible in your windows |

> [!IMPORTANT]
> Apart from `#{buffer}` and `#{buffers}`, editor context is a snapshot taken when you send the message. To share the latest state, use it again in a new message

To add your own, see [Editor Context](/configuration/chat-buffer#editor-context).

## #buffer

`#{buffer}` shares the last buffer you were in. To share a different open buffer, add its name after a colon:

| Syntax | Shares |
| --- | --- |
| `#{buffer}` | The last buffer you were in |
| `#{buffer:init.lua}` | The open buffer with this file name |
| `#{buffer:src/main.rs}` | The open buffer at this path |

A path can be absolute, relative to the current working directory, or the file's parent directory and name. Only open buffers are matched. If none match, nothing is shared and a warning is logged.

To compare two buffers:

```md
Compare #{buffer:old_file.js} with #{buffer:new_file.js} and explain the differences.
```

> [!TIP]
> To pick several buffers at once, use the [/buffer](/usage/chat-buffer/slash-commands#buffer) slash command

### Syncing

A shared buffer is _synced_ with the chat, so the LLM sees your edits on later turns. A parameter after the editor context sets what's sent:

| Parameter | Sends |
| --- | --- |
| `{diff}` | Only what's changed since the last turn. The default |
| `{all}` | The whole buffer on every turn |

`{diff}` uses fewer tokens on large files. `{all}` always gives the LLM a complete, up-to-date copy. Parameters work with a named buffer too:

```md
#{buffer}{all}
#{buffer:config.lua}{all}
```

Use `gba` and `gbd` on an item in the [Context](/usage/chat-buffer/#context) blockquote to toggle syncing after it's shared. To change the default parameter, see [Syncing](/configuration/chat-buffer#syncing).

## #buffers

`#{buffers}` shares every open buffer, synced in the same way as [#buffer](#syncing) and with the same `{diff}` and `{all}` parameters:

```md
#{buffers} can you explain what's going on in these files?
```

Buffers with the `nofile`, `quickfix`, `prompt` or `popup` buftype, and the `codecompanion`, `help` or `terminal` filetype, are skipped. These lists live in `interactions.shared.editor_context.opts.excluded`.

## #code_review

`#{code_review}` shares your [code review](/usage/code-review). Every pending comment you've left with `:CodeCompanionCodeReview Comment` is sent, and the round closes off so the next review only shows what changes next:

```md
Please action #{code_review}
```

Each comment reaches the LLM with the file, the line range and the code you commented on. The chat buffer shows a shorter version without the code, so you can scroll back through earlier rounds and see what you asked for.

> [!NOTE]
> Sharing your review clears the pending comments and their virtual text. Like a pull request review, it also approves everything you didn't comment on

## #diagnostics

`#{diagnostics}` shares every diagnostic in the last buffer you were in, from LSP servers or any other source, along with the lines of code each one points at:

```md
#{diagnostics} can you explain the LSP errors in this file and how to fix them?
```

To share another open buffer's diagnostics, name it in the same way as [#buffer](#buffer): `#{diagnostics:init.lua}`. If no buffer matches, the last buffer you were in is used.

> [!TIP]
> The [Action Palette](/usage/action-palette) has a prompt that asks an LLM to explain the diagnostics in a visual selection

## #diff

`#{diff}` shares the git diff of the current working directory, including staged and unstaged changes. Use it to ask for a commit message or feedback on your recent changes:

```md
Sharing the latest git diff with you #{diff}
```

## #messages

`#{messages}` shares Neovim's message history, as shown by `:messages`. Use it when an error has been written there:

```md
Can you explain the error I've just observed in Neovim? #{messages}
```

## #quickfix

`#{quickfix}` shares the files in the quickfix list, such as compiler errors, search results or diagnostics across several files:

```md
The relevant output from my quickfix list has now been shared with you #{quickfix}
```

Files under 100 lines are shared in full, with their entries listed above. In larger files, entries are grouped by the Tree-sitter symbol they sit in, and only that code is shared. An entry that points at a file rather than a line shares the whole file.

## #selection

`#{selection}` shares your current or most recent visual selection, so you can ask about a piece of code without sharing the whole buffer. The selection is captured when you open or toggle a chat buffer:

```md
Sharing the relevant code with you #{selection}
```

## #terminal

`#{terminal}` shares the output from the last terminal buffer you entered Terminal mode in. Later uses only share the output added since the last time. Use it for test results, build output or command-line errors:

```md
This was the output in my terminal #{terminal}
```

## #viewport

`#{viewport}` shares the code visible in your windows when you send the message. The chat buffer, and any buffer [#buffers](#buffers) skips, is left out:

```md
Sharing what I can see in Neovim #{viewport}
```
