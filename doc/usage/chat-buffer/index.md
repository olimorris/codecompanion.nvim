# Using the Chat Buffer

> [!NOTE]
> The chat buffer has a filetype of `codecompanion` and a buftype of `nofile`

You can open a chat buffer with the `:CodeCompanionChat` command or with `require("codecompanion").chat()`. You can toggle the visibility of the chat buffer with `:CodeCompanionChat Toggle` or `require("codecompanion").toggle()`.

The chat buffer uses markdown as its syntax and `H2` headers separate the user and LLM's responses. The user's responses are parsed by [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) and sent via an adapter to an LLM for a response which is then streamed back into the buffer. A response is sent to the LLM by pressing `<CR>` or `<C-s>`. This can of course be changed as per the [keymaps](#keymaps) section.

## Messages

Messages which are sent to the LLM sit under `H2` headers in the chat buffer. However, when adding system prompts or context to the chat buffer via [Slash Commands](/usage/chat-buffer/slash-commands), some messages will be hidden. Using the keymap `gd` (to debug the chat buffer), you are able to see the full contents of the messages table.

## Completion

<img src="https://github.com/user-attachments/assets/02b4d5e2-3b40-4044-8a85-ccd6dfa6d271" />

The plugin supports multiple completion plugins out of the box. By default, the plugin will look to setup [blink.cmp](https://github.com/Saghen/blink.cmp) before trying to setup [nvim-cmp](https://github.com/hrsh7th/nvim-cmp). If you don't use a completion plugin, then you can use native completions with no setup, invoking them with `<C-_>` from within the chat buffer.

## Keymaps

The plugin has a host of keymaps available in the chat buffer. Pressing `?` in the chat buffer will conveniently display all of them to you.

The keymaps available to the user in normal mode are:

- `<CR>|<C-s>` to send a message to the LLM
- `<C-c>` to close the chat buffer
- `q` to stop the current request
- `ga` to change the adapter for the currentchat
- `gc` to insert a codeblock in the chat buffer
- `gd` to view/debug the chat buffer's contents
- `gf` to fold any codeblocks in the chat buffer
- `gp` to pin a reference to the chat buffer
- `gr` to regenerate the last response
- `gs` to toggle the system prompt on/off
- `gx` to clear the chat buffer's contents
- `gy` to yank the last codeblock in the chat buffer
- `[[` to move to the previous header
- `]]` to move to the next header
- `{` to move to the previous chat
- `}` to move to the next chat

## References

<img src="https://github.com/user-attachments/assets/1b44afe1-13f8-4c0f-9199-cb32439eb09e" />

Sharing context with an LLM is a crucial in order to generate useful responses. In the plugin, references are defined as output that is shared with a chat buffer via a _Variable_, _Slash Command_ or _Agent/Tool_. They appear in a blockquote entitled `Sharing`. In essence, this is context that you're sharing with an LLM.

References can be removed from the chat buffer by simply deleting them. On the next turn, the context will be removed from the message history.

> [!NOTE]
> Pinned references only work with buffer and file references

References can also be pinned to a chat buffer with the `gp` keymap. Pinning results in the content from a buffer or a file, being reloaded and shared with the LLM before a response is sent. The advantage of this is that the LLM always has the latest data from that source, saving the user from manually re-adding it to the chat buffer.

## Settings

<img src="https://github.com/user-attachments/assets/01f1e482-1f7b-474f-ae23-f25cc637f40a" />

When conversing with an LLM, it can be useful to tweak model settings in between responses in order to generate the perfect output. If settings are enabled (`display.chat.show_settings = true`), then a yaml block will be present at the top of the chat buffer which can be modified in between responses. The yaml block is simply a representation of an adapter's schema table.

