# History

[![Tests](https://github.com/ravitemer/codecompanion-history.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/ravitemer/codecompanion-history.nvim/actions)

The [History extension](https://github.com/ravitemer/codecompanion-history.nvim) for CodeCompanion provides persistent chat history management, allowing you to save, browse, and restore chat sessions across Neovim restarts. It includes automatic title generation and flexible storage options.

<p>
<video controls muted src="https://github.com/user-attachments/assets/04a6ad1f-8351-4381-ae60-00c352a1670c"></video>
</p>

## Features

- 💾 Flexible chat saving:
  - Automatic session saving (can be disabled)
  - Manual save with dedicated keymap
- 🎯 Smart title generation for chats
- 🔄 Continue from where you left
- 📚 Browse saved chats with preview
- 🔍 Multiple picker interfaces
- ⌛ Optional automatic chat expiration
- ⚡ Restore chat sessions with full context and tools state

The following CodeCompanion features are preserved when saving and restoring chats:

| Feature | Status | Notes |
|---------|--------|-------|
|  System Prompts | ✅  | System prompt used in the chat |
|  Messages History | ✅  | All messages |
|  LLM Adapter | ✅  | The specific adapter used for the chat |
|  LLM Settings | ✅  | Model, temperature and other adapter settings |
|  Tools | ✅  | Tool schemas and their system prompts |
|  Tool Outputs | ✅  | Tool execution results |
|  Variables | ✅  | Variables used in the chat |
|  References | ✅  | Code snippets and command outputs added via slash commands |
|  Pinned References | ✅  | Pinned references |
|  Watchers | ⚠  | Saved but requires original buffer context to resume watching |

> [!NOTE]
> As this is an extension that deeply integrates with CodeCompanion's internal APIs, occasional compatibility issues may arise when CodeCompanion updates. If you encounter any bugs or unexpected behavior, please [raise an issue](https://github.com/ravitemer/codecompanion-history.nvim/issues) to help us maintain compatibility.

## Installation

First, install the plugin

```lua
{
    "olimorris/codecompanion.nvim",
    dependencies = {
        --other plugins
        "ravitemer/codecompanion-history.nvim"
    }
}
```

For detailed information, please refer to the [documentation](https://github.com/ravitemer/codecompanion-history.nvim#installation).

Next, register history as an extension in your CodeCompanion config:

```lua
require("codecompanion").setup({
    extensions = {
        history = {
            enabled = true,
            opts = {
                -- Keymap to open history from chat buffer (default: gh)
                keymap = "gh",
                -- Keymap to save the current chat manually (when auto_save is disabled)
                save_chat_keymap = "sc",
                -- Save all chats by default (disable to save only manually using 'sc')
                auto_save = true,
                -- Number of days after which chats are automatically deleted (0 to disable)
                expiration_days = 0,
                -- Picker interface ("telescope" or "snacks" or "fzf-lua" or "default")
                picker = "telescope",
                -- Automatically generate titles for new chats
                auto_generate_title = true,
                ---On exiting and entering neovim, loads the last chat on opening chat
                continue_last_chat = false,
                ---When chat is cleared with `gx` delete the chat from history
                delete_on_clearing_chat = false,
                ---Directory path to save the chats
                dir_to_save = vim.fn.stdpath("data") .. "/codecompanion-history",
                ---Enable detailed logging for history extension
                enable_logging = false,
            }
        }
    }
})
```

## Usage 

#### 🎯 Commands

- `:CodeCompanionHistory` - Open the history browser

#### ⌨️ Chat Buffer Keymaps

- `gh` - Open history browser (customizable via `opts.keymap`)
- `sc` - Save current chat manually (customizable via `opts.save_chat_keymap`)

#### 📚 History Browser

The history browser shows all your saved chats with:
- Title (auto-generated or custom)
- Last updated time  
- Preview of chat contents

Actions in history browser:
- `<CR>` - Open selected chat
- Normal mode:
  - `d` - Delete selected chat(s)
  - `r` - Rename selected chat
- Insert mode:
  - `<M-d>` (Alt+d) - Delete selected chat(s)
  - `<M-r>` (Alt+r) - Rename selected chat

You can use `<Tab>` to select multiple chats for deletion.

> Note: Delete and rename actions are not available for the default picker.

#### 🔧 API

The history extension exports the following functions that can be accessed via `require("codecompanion").extensions.history`:

```lua
-- Get the storage location for saved chats
get_location(): string?

-- Save a chat to storage (uses last chat if none provided)
save_chat(chat?: CodeCompanion.Chat)

-- Get metadata for all saved chats
get_chats(): table<string, ChatIndexData>

-- Load a specific chat by its save_id
load_chat(save_id: string): ChatData?

-- Delete a chat by its save_id
delete_chat(save_id: string): boolean
```

## Additional Resources

- Visit [codecompanion-history.nvim](https://github.com/ravitemer/codecompanion-history.nvim) to see how it works.
- Found a bug? [Raise an issue](https://github.com/ravitemer/codecompanion-history.nvim/issues).
