# Configuring the Chat Buffer

<p align="center">
  <img src="https://github.com/user-attachments/assets/597299d2-36b3-469e-b69c-4d8fd14838f8" alt="Chat buffer">
</p>

By default, CodeCompanion provides a "chat" strategy that uses a dedicated Neovim buffer for conversational interaction with your chosen LLM. This buffer can be customized according to your preferences.

## Keymaps

You can define or override the default keymaps to send messages, regenerate responses, close the buffer, etc. Example:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      keymaps = {
        send = {
          modes = { n = "<C-s>", i = "<C-s>" },
        },
        close = {
          modes = { n = "<C-c>", i = "<C-c>" },
        },
        -- Add further custom keymaps here
      },
    },
  },
})
```

The keymaps are mapped to `<C-s>` for sending a message and `<C-c>` for closing in both normal and insert modes.

## Variables

Variables are placeholders inserted into the chat buffer (using `#`). They provide contextual code or information about the current Neovim state. For instance, the built-in `#buffer` variable sends the current buffer’s contents to the LLM.

You can even define your own variables to share specific content:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      variables = {
        ["my_var"] = {
          callback = function()
            return "Your custom content here."
          end,
          description = "Explain what my_var does",
          opts = {
            contains_code = false,
          },
        },
      },
    },
  },
})
```

## Slash Commands

Slash Commands (invoked with `/`) let you dynamically insert context into the chat buffer, such as file contents or date/time.

The plugin supports providers like `telescope`, `mini_pick`, `fzf_lua` and `snacks` (as in snacks.nvim). Please see the [Chat Buffer](/usage/chat-buffer/index) usage section for full details:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      slash_commands = {
        ["file"] = {
          callback = "strategies.chat.slash_commands.file",
          description = "Select a file using Telescope",
          opts = {
            provider = "telescope", -- Other options include 'default', 'mini_pick', 'fzf_lua', snacks
            contains_code = true,
          },
        },
      },
    },
  },
})
```

You can also add your own slash commands:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      slash_commands = {
        ["mycmd"] = {
          description = "Describe what mycmd inserts",
          callback = function()
            return "Custom context or data"
          end,
          opts = {
            contains_code = true,
          },
        },
      },
    },
  },
})
```

## Agents and Tools

Tools perform specific tasks (e.g., running shell commands, editing buffers, etc.) when invoked by an LLM. You can group them into an Agent and both can be referenced with `@` when in the chat buffer:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      agents = {
        ["my_agent"] = {
          description = "A custom agent combining tools",
          system_prompt = "Describe what the agent should do",
          tools = {
            "cmd_runner",
            "editor",
            -- Add your own tools or reuse existing ones
          },
        },
      },
      tools = {
        ["my_tool"] = {
          description = "Run a custom task",
          callback = function(command)
            -- Perform the custom task here
            return "Tool result"
          end,
        },
      },
    },
  },
})
```

When users introduce the agent `@my_agent` in the chat buffer, it can call the tools you listed (like `@my_tool`) to perform tasks on your code.

## Layout

You can change the appearance of the chat buffer by changing the `display.chat.window` table in your configuration:

```lua
require("codecompanion").setup({
  display = {
    chat = {
      -- Options to customize the UI of the chat buffer
      window = {
        layout = "vertical", -- float|vertical|horizontal|buffer
        position = nil, -- left|right|top|bottom (nil will default depending on vim.opt.splitright|vim.opt.splitbelow)
        border = "single",
        height = 0.8,
        width = 0.45,
        relative = "editor",
        opts = {
          breakindent = true,
          cursorcolumn = false,
          cursorline = false,
          foldcolumn = "0",
          linebreak = true,
          list = false,
          numberwidth = 1,
          signcolumn = "no",
          spell = false,
          wrap = true,
        },
      },

      ---Customize how tokens are displayed
      ---@param tokens number
      ---@param adapter CodeCompanion.Adapter
      ---@return string
      token_count = function(tokens, adapter)
        return " (" .. tokens .. " tokens)"
      end,
    },
  }
}),
```

## Diff

> [!NOTE]
> Currently the plugin only supports native Neovim diff or [mini.diff](https://github.com/echasnovski/mini.diff)

If you utilize the `@editor` tool, then the plugin can update a given chat buffer. A diff will be created so you can see the changes made by the LLM.

There are a number of diff settings available to you:

```lua
require("codecompanion").setup({
  display = {
    chat = {
      diff = {
        enabled = true,
        close_chat_at = 240, -- Close an open chat buffer if the total columns of your display are less than...
        layout = "vertical", -- vertical|horizontal split for default provider
        opts = { "internal", "filler", "closeoff", "algorithm:patience", "followwrap", "linematch:120" },
        provider = "default", -- default|mini_diff
      },
    },
  },
}),
```

## UI

As the Chat Buffer uses markdown as its syntax, you can use popular rendering plugins to improve the UI:

**[render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim)**

```lua
{
  "MeanderingProgrammer/render-markdown.nvim",
  ft = { "markdown", "codecompanion" }
},
```

**[markview.nvim](https://github.com/OXY2DEV/markview.nvim)**

```lua
{
  "OXY2DEV/markview.nvim",
  ft = { "markdown", "codecompanion" },
  opts = {
    filetypes = { "markdown", "codecompanion" },
    buf_ignore = {},
  },
},
```

## Additional Options

There are also a number of other options that you can customize:

```lua
require("codecompanion").setup({
  display = {
    chat = {
      intro_message = "Welcome to CodeCompanion ✨! Press ? for options",
      show_header_separator = false, -- Show header separators in the chat buffer? Set this to false if you're using an external markdown formatting plugin
      separator = "─", -- The separator between the different messages in the chat buffer
      show_references = true, -- Show references (from slash commands and variables) in the chat buffer?
      show_settings = false, -- Show LLM settings at the top of the chat buffer?
      show_token_count = true, -- Show the token count for each response?
      start_in_insert_mode = false, -- Open the chat buffer in insert mode?
    },
  },
}),
```
