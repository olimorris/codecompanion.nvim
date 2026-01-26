---
description: How to customize the user interface (UI) of CodeCompanion
---

# User Interface

<p>
  <video muted controls loop src="https://github.com/user-attachments/assets/a37180a0-0f1b-4ffb-8fae-44669e9d3df7"></video>
</p>

CodeCompanion aims to keep any changes to the user's UI to a minimum. Aesthetics, especially in Neovim, are highly subjective. So whilst it won't set much by default, it does endeavour to allow users to hook into the plugin and customize the UI to their liking via [Events](/usage/events).

### Metadata

CodeCompanion exposes a global dictionary, `_G.codecompanion_chat_metadata` which users can leverage throughout their configuration. Using the chat buffer's buffer number as the key, the dictionary contains:

- `adapter` - The `name` and `model` of the chat buffer's current adapter
- `context_items` - The number of context items current in the chat buffer
- `cycles` - The number of cycles (User->LLM->User) that have taken place in the chat buffer
- `id` - The ID of the chat buffer
- `tokens` - The running total of tokens for the chat buffer
- `tools` - The number of tools in the chat buffer

You can also leverage `_G.codecompanion_current_context` to fetch the number of the buffer which the `#{buffer}` variable points at.

The video at the top of this page shows how the author has incorporated the metadata into their statusline.

### Highlight Groups

The plugin sets the following highlight groups during setup:

- `CodeCompanionChatInfo` - Information messages in the chat buffer
- `CodeCompanionChatInfoBanner` - Banner showing useful information in the chat buffer
- `CodeCompanionChatError` - Error messages in the chat buffer
- `CodeCompanionChatWarn` - Warning messages in the chat buffer
- `CodeCompanionChatSubtext` - Messages that appear under the information, error or warning messages in the chat buffer
- `CodeCompanionChatFold` - For any folds in the chat buffer (not including tool output)
- `CodeCompanionChatHeader` - The headers in the chat buffer
- `CodeCompanionChatSeparator` - Separator between headings in the chat buffer
- `CodeCompanionChatTokens` - Virtual text in the chat buffer showing the token count
- `CodeCompanionChatTool` - Tools in the chat buffer
- `CodeCompanionChatToolGroups` - Tool groups in the chat buffer
- `CodeCompanionChatVariable` - Variables in the chat buffer
- `CodeCompanionVirtualText` - All other virtual text in the plugin

