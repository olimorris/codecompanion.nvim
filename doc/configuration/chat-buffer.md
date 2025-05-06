# Configuring the Chat Buffer

<p align="center">
  <img src="https://github.com/user-attachments/assets/597299d2-36b3-469e-b69c-4d8fd14838f8" alt="Chat buffer">
</p>

By default, CodeCompanion provides a "chat" strategy that uses a dedicated Neovim buffer for conversational interaction with your chosen LLM. This buffer can be customized according to your preferences.

Please refer to the [config.lua](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua#L42-L392) file for a full list of all configuration options.

## Keymaps

You can define or override the [default keymaps](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua#L178) to send messages, regenerate responses, close the buffer, etc. Example:

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

[Variables](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua#L90) are placeholders inserted into the chat buffer (using `#`). They provide contextual code or information about the current Neovim state. For instance, the built-in `#buffer` variable sends the current buffer’s contents to the LLM.

You can even define your own variables to share specific content:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      variables = {
        ["my_var"] = {
          ---Ensure the file matches the CodeCompanion.Variable class
          ---@return string|fun(): nil
          callback = "/Users/Oli/Code/my_var.lua",
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

[Slash Commands](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua#L114) (invoked with `/`) let you dynamically insert context into the chat buffer, such as file contents or date/time.

The plugin supports providers like `telescope`, `mini_pick`, `fzf_lua` and `snacks` (as in snacks.nvim). By default, the plugin will automatically detect if you have any of those plugins installed and duly select them. Failing that, the in-build `default` provider will be used. Please see the [Chat Buffer](/usage/chat-buffer/index) usage section for full details:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      slash_commands = {
        ["file"] = {
          -- Location to the slash command in CodeCompanion
          callback = "strategies.chat.slash_commands.file",
          description = "Select a file using Telescope",
          opts = {
            provider = "telescope", -- Can be "default", "telescope", "fzf_lua", "mini_pick" or "snacks"
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
        ["git_files"] = {
          description = "List git files",
          ---@param chat CodeCompanion.Chat
          callback = function(chat)
            local handle = io.popen("git ls-files")
            if handle ~= nil then
              local result = handle:read("*a")
              handle:close()
              chat:add_reference({ role = "user", content = result }, "git", "<git_files>")
            else
              return vim.notify("No git files available", vim.log.levels.INFO, { title = "CodeCompanion" })
            end
          end,
          opts = {
            contains_code = false,
          },
        },
      },
    },
  },
})
```

Credit to [@lazymaniac](https://github.com/lazymaniac) for the [inspiration](https://github.com/olimorris/codecompanion.nvim/discussions/958).

> [!NOTE]
> You can also point the callback to a lua file that resides within your own configuration

## Agents and Tools

[Tools](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua#L55) perform specific tasks (e.g., running shell commands, editing buffers, etc.) when invoked by an LLM. Multiple tools can be grouped together. Both can be referenced with `@` when in the chat buffer:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      tools = {
        ["my_tool"] = {
          description = "Run a custom task",
          callback = require("user.codecompanion.tools.my_tool")
        },
        groups = {
          ["my_group"] = {
            description = "A custom agent combining tools",
            system_prompt = "Describe what the agent should do",
            tools = {
              "cmd_runner",
              "editor",
              -- Add your own tools or reuse existing ones
            },
          },
        },
      },
    },
  },
})
```

When users introduce the agent `@my_agent` in the chat buffer, it can call the tools you listed (like `@my_tool`) to perform tasks on your code.

A tool is a [`CodeCompanion.Tool`](/extending/tools) table with specific keys that define the interface and workflow of the tool. The table can be resolved using the `callback` option. The `callback` option can be a table itself or either a function or a string that points to a luafile that return the table.

Some tools, such as the [@cmd_runner](/usage/chat-buffer/agents.html#cmd-runner), require the user to approve any commands before they're executed. This can be changed by altering the config for each tool:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      tools = {
        ["cmd_runner"] = {
          opts = {
            requires_approval = false,
          },
        },
      }
    }
  }
})
```

## Prompt Decorator

It can be useful to decorate your prompt, prior to sending to an LLM, with additional information. For example, the GitHub Copilot prompt in VS Code, wraps a user's prompt between `<prompt></prompt>` tags presumably to differentiate the user's ask from additional context. This can also be achieved in CodeCompanion:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      opts = {
        ---Decorate the user message before it's sent to the LLM
        ---@param message string
        ---@param adapter CodeCompanion.Adapter
        ---@param context table
        ---@return string
        prompt_decorator = function(message, adapter, context)
          return string.format([[<prompt>%s</prompt>]], message)
        end,
      }
    }
  }
})
```

The decorator function also has access to the adapter in the chat buffer alongside the [context](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/utils/context.lua#L121-L137) table (which refreshes when a user toggles the chat buffer).

## Layout

You can change the [appearance](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua#L903) of the chat buffer by changing the `display.chat.window` table in your configuration:

```lua
require("codecompanion").setup({
  display = {
    chat = {
      -- Change the default icons
      icons = {
        pinned_buffer = " ",
        watched_buffer = "👀 ",
      },

      -- Alter the sizing of the debug window
      debug_window = {
        ---@return number|fun(): number
        width = vim.o.columns - 5,
        ---@return number|fun(): number
        height = vim.o.lines - 2,
      },

      -- Options to customize the UI of the chat buffer
      window = {
        layout = "vertical", -- float|vertical|horizontal|buffer
        position = nil, -- left|right|top|bottom (nil will default depending on vim.opt.plitright|vim.opt.splitbelow)
        border = "single",
        height = 0.8,
        width = 0.45,
        relative = "editor",
        full_height = true, -- when set to false, vsplit will be used to open the chat buffer vs. botright/topleft vsplit
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
  },
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
    diff = {
      enabled = true,
      close_chat_at = 240, -- Close an open chat buffer if the total columns of your display are less than...
      layout = "vertical", -- vertical|horizontal split for default provider
      opts = { "internal", "filler", "closeoff", "algorithm:patience", "followwrap", "linematch:120" },
      provider = "default", -- default|mini_diff
    },
  },
}),
```

## UI

### User and LLM Roles

The chat buffer places user and LLM responses under a `H2` header. These can be customized in the configuration:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      roles = {
        ---The header name for the LLM's messages
        ---@type string|fun(adapter: CodeCompanion.Adapter): string
        llm = function(adapter)
          return "CodeCompanion (" .. adapter.formatted_name .. ")"
        end,

        ---The header name for your messages
        ---@type string|fun(adapter: CodeCompanion.Adapter): string
        user = function(adapter)
			return vim.env.USER:gsub("^%l", string.upper)
        end,
      }
    }
  }
})
```

By default, the LLM's responses will be placed under a header such as `CodeCompanion (DeepSeek)`, leveraging the current adapter in the chat buffer. This option can be in the form of a string or a function that returns a string. If you opt for a function, the first parameter will always be the adapter from the chat buffer.

### Markdown Rendering

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
  lazy = false,
  opts = {
    preview = {
      filetypes = { "markdown", "codecompanion" },
      ignore_buftypes = {},
    },
  },
},
```

### Auto scrolling

By default, the page scrolls down automatically as the response streams, with the cursor placed at the end.
This can be distracting if you are focusing on the earlier content while the page scrolls up away during a long response.
You can disable this behavior using a flag:

```lua
require("codecompanion").setup({
  display = {
    chat = {
      auto_scroll = false
    },
  },
}),
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
