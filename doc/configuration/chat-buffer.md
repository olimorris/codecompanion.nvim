# Configuring the Chat Buffer

By default, CodeCompanion provides a "chat" strategy that uses a dedicated Neovim buffer for conversational interaction with your chosen LLM. This buffer can be customized according to your preferences.

Please refer to the [config.lua](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua#L42-L392) file for a full list of all configuration options.

## Keymaps

> [!NOTE]
> The plugin scopes CodeCompanion specific keymaps to the _chat buffer_ only.

You can define or override the [default keymaps](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua#L178) to send messages, regenerate responses, close the buffer, etc. Example:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      keymaps = {
        send = {
          modes = { n = "<C-s>", i = "<C-s>" },
          opts = {},
        },
        close = {
          modes = { n = "<C-c>", i = "<C-c>" },
          opts = {},
        },
        -- Add further custom keymaps here
      },
    },
  },
})
```

The keymaps are mapped to `<C-s>` for sending a message and `<C-c>` for closing in both normal and insert modes. To set other `:map-arguments`, you can use the optional `opts` table which will be fed to `vim.keymap.set`.

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
            --has_params = true,    -- Set this if your variable supports parameters
            --default_params = nil, -- Set default parameters
          },
        },
      },
    },
  },
})
```

## Slash Commands

[Slash Commands](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua#L114) (invoked with `/`) let you dynamically insert context into the chat buffer, such as file contents or date/time.

The plugin supports providers like [telescope](https://github.com/nvim-telescope/telescope.nvim), [mini_pick](https://github.com/echasnovski/mini.pick), [fzf_lua](https://github.com/ibhagwan/fzf-lua) and [snacks.nvim](https://github.com/folke/snacks.nvim). By default, the plugin will automatically detect if you have any of those plugins installed and duly set them as the default provider. Failing that, the in-built `default` provider will be used. Please see the [Chat Buffer](/usage/chat-buffer/index) usage section for information on how to use Slash Commands.

You can configure Slash Commands with:

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

> [!IMPORTANT]
> Each slash command may have their own unique configuration so be sure to check out the [config.lua](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua) file

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

### Keymaps

Slash Commands can also be called via keymaps, in the chat buffer. Simply add a `keymaps` table to the Slash Command you'd like to call. For example:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      slash_commands = {
        ["buffer"] = {
          keymaps = {
            modes = {
              i = "<C-b>",
              n = { "<C-b>", "gb" },
            },
          },
        },
      },
    },
  },
})

```

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
              "insert_edit_into_file",
              -- Add your own tools or reuse existing ones
            },
            opts = {
              collapse_tools = true, -- When true, show as a single group reference instead of individual tools
            },
          },
        },
      },
    },
  },
})
```

When users introduce the group, `my_group`, in the chat buffer, it can call the tools you listed (such as `cmd_runner`) to perform tasks on your code.

A tool is a [`CodeCompanion.Tool`](/extending/tools) table with specific keys that define the interface and workflow of the tool. The table can be resolved using the `callback` option. The `callback` option can be a table itself or either a function or a string that points to a luafile that return the table.

### Tool Conditionals

Tools can also be conditionally enabled:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      tools = {
        ["grep_search"] = {
          ---@return boolean
          enabled = function()
            return vim.fn.executable("rg") == 1
          end,
        },
      }
    }
  }
})
```

This is useful to ensure that a particular dependency is installed on the machine. After the user has installed the dependency, the `:CodeCompanionChat RefreshCache` command can be used to refresh the cache's across chat buffers.

### Approvals

Some tools, such as [cmd_runner](/usage/chat-buffer/agents.html#cmd-runner), require the user to approve any commands before they're executed. This can be changed by altering the config for each tool:

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

You can also force any tool to require your approval by adding in `opts.requires_approval = true`.

### Auto Submit Tool Output (Recursion)

When a tool executes, it can be useful to automatically send its output back to the LLM. This can be achieved by the following options in your configuration:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      tools = {
        opts = {
          auto_submit_errors = true, -- Send any errors to the LLM automatically?
          auto_submit_success = true, -- Send any successful output to the LLM automatically?
        },
      }
    }
  }
})
```

### Automatically Add Tools to Chat

You can configure the plugin to automatically add tools and tool groups to new chat buffers:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      tools = {
        opts = {
          default_tools = {
            "my_tool",
            "my_tool_group"
          }
        },
      }
    }
  }
})
```

This also works for [extensions](/configuration/extensions).

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
        buffer_pin = " ",
        buffer_watch = "👀 ",
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
        position = nil, -- left|right|top|bottom (nil will default depending on vim.opt.splitright|vim.opt.splitbelow)
        border = "single",
        height = 0.8,
        width = 0.45,
        relative = "editor",
        full_height = true, -- when set to false, vsplit will be used to open the chat buffer vs. botright/topleft vsplit
        sticky = false, -- when set to true and `layout` is not `"buffer"`, the chat buffer will remain opened when switching tabs
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

If you utilize the `insert_edit_into_file` tool, then the plugin can update a given chat buffer. A diff will be created so you can see the changes made by the LLM.

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

## User Interface (UI)

> [!NOTE]
> The [additional plugins](/installation#additional-plugins) section contains installation instructions for some popular markdown rendering plugins

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
        ---@type string
        user = "Me",
      }
    }
  }
})
```

By default, the LLM's responses will be placed under a header such as `CodeCompanion (DeepSeek)`, leveraging the current adapter in the chat buffer. This option can be in the form of a string or a function that returns a string. If you opt for a function, the first parameter will always be the adapter from the chat buffer.

The user role is currently only available as a string.

### Completion

By default, CodeCompanion looks to use the fantastic [blink.cmp](https://github.com/Saghen/blink.cmp) plugin to complete variables, slash commands and tools. However, you can override this in your config:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      opts = {
        completion_provider = "cmp", -- blink|cmp|coc|default
      }
    }
  }
})
```

The plugin also supports [nvim-cmp](https://github.com/hrsh7th/nvim-cmp), a native completion solution (`default`), and [coc.nvim](https://github.com/neoclide/coc.nvim).

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

## Jump Action

The jump action (the command/function triggered by the `gR` keymap) can be
customised as follows:
```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      opts = {
        goto_file_action = 'tabnew', -- this will always open the file in a new tab
      },
    },
  },
})
```

This can either be a string (denoting a VimScript command), or a function that
takes a single parameter (the path to the file to jump to). The default action
is to jump to an existing tab if the file is already opened, and open a new tab
otherwise.
