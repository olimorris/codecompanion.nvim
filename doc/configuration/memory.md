---
description: Configure memory (such as CLAUDE.md or Cursor rules) in CodeCompanion
---

# Configuring Memory

Fundamentally, memory is a way of adding persistent context to a chat buffer. CodeCompanion uses _groups_ to create a collection of files that can be added to chats. Groups can also be linked to a _parser_ which can offer post-processing customization such as parsing file paths and adding them as buffers or files to the chat buffer.

## Enabling Memory

By default, memory is not enabled in the chat buffer. To enable it:

```lua
require("codecompanion").setup({
  memory = {
    opts = {
      chat = {
        enabled = true,
      },
    },
  },
})
```

Once enabled, the plugin will look to load a common, or default, set of files every time a chat buffer is created.

> [!INFO]
> Refer to the [config.lua](https://github.com/olimorris/codecompanion.nvim/blob/5807e0457111f0de267fc9a6543b41fae0f5c2b1/lua/codecompanion/config.lua#L1167-L1179) file for the full set of files included in the default group.

You can also conditionally determine if memory should be added to a chat buffer:

```lua
require("codecompanion").setup({
  memory = {
    opts = {
      chat = {
        ---Function to determine if memory should be added to a chat buffer
        ---This requires `enabled` to be true
        ---@param chat CodeCompanion.Chat
        ---@return boolean
        condition = function(chat)
          return chat.adapter.type ~= "acp"
        end,
      },
    },
  },
})
```

The example above is taken from the config itself, as by default, the plugin will not add memory to [ACP](/usage/chat-buffer/agents) adapters.

## Working with Groups

In the plugin, memory groups are a collection of files and/or directories. Below is an example of what a `claude` group might look like:

```lua
require("codecompanion").setup({
  memory = {
    claude = {
      description = "Memory files for Claude Code users",
      files = {
        "~/.claude/CLAUDE.md",
        "CLAUDE.md",
        "CLAUDE.local.md",
      },
    },
  },
})
```

You'll notice that the file paths can be local to the current working directory or point to an absolute location.

### Conditionally Enabling Groups

You can also conditionally enable memory groups. For instance, the default `CodeCompanion` group has the following conditional:

```lua
require("codecompanion").setup({
  memory = {
    CodeCompanion = {
      description = "CodeCompanion plugin memory files",
      ---@return boolean
      enabled = function()
        -- Don't show this to users who aren't working on CodeCompanion itself
        return vim.fn.getcwd():find("codecompanion", 1, true) ~= nil
      end,
      files = {}, -- removed for brevity
    },
  },
})
```

### Nesting Groups

It's also possible to nest groups within a group. This can be a convenient way of applying the same conditional to multiple groups alongside keeping your config clean:

```lua
require("codecompanion").setup({
  memory = {
    CodeCompanion = {
      description = "CodeCompanion plugin memory files",
      parser = "claude",
      files = {
        ["acp"] = {
          description = "The ACP implementation",
          files = {
            ".codecompanion/acp/acp.md",
          },
        },
      },
    },
  },
})
```

In the example above, the main group is `CodeCompanion` and a sub-group, `acp`, sits within the files table. The `claude` parser sits across all of the groups.

When using the _Action Palette_ or the slash command, the plugin will extract these nested groups and display them.


## Parsers

> [!NOTE]
> Parsers are an optional addition to memory in the plugin.

Currently, the plugin has two in-built parsers:

- `claude` - which will import files into the chat buffer in the same way Claude Code [does](https://docs.anthropic.com/en/docs/claude-code/memory#claude-md-imports). Note, this requires memory to be `markdown` files
- `none` - a blank parser which can be used to overwrite parsers that have been set on the default memory groups

Please see the guide on [Creating Memory Parsers](/extending/parsers) to understand how you can create and apply your own.

### Applying Parsers

You can apply parsers at a group level, to ensure that all files in the group are parsed in the same way:

```lua
require("codecompanion").setup({
  memory = {
    claude = {
      description = "Memory files for Claude Code users",
      parser = "claude",
      files = {
        "CLAUDE.md",
        "CLAUDE.local.md",
        "~/.claude/CLAUDE.md",
      },
    },
  },
})
```

In the example above, every file within the group will be sent through the `claude` parser before being added to the chat buffer.

Alternatively, you can apply parsers at a file level.

```lua
require("codecompanion").setup({
  memory = {
    default = {
      description = "Collection of common files for all projects",
      files = {
        { path = "CLAUDE.md", parser = "claude" },
        { path = "CLAUDE.local.md", parser = "claude" },
        { path = "~/.claude/CLAUDE.md", parser = "claude" },
      },
    },
  },
})
```

Or combine both approaches, whereby the parsers at a file level will take precedence.

### Disabling Parsers

To disable a parser against a memory group, simply assign it a parser of `none`.

## Changing Defaults

### Groups

The plugin will look to load the `default` memory group by default. This can be changed by:

```lua
require("codecompanion").setup({
  memory = {
    opts = {
      chat = {
        default_memory = "my_new_group",
      },
    },
  },
})
```

Alternatively, you can select multiple groups:

```lua
require("codecompanion").setup({
  memory = {
    opts = {
      chat = {
        default_memory = { "default", "my_new_group" },
      },
    },
  },
})
```

### Buffers and Files

If a parsed memory group contains links to files and they are Neovim buffers, you can set specific parameters, such as a [pin or a watch](/usage/chat-buffer/variables#with-parameters):

```lua
require("codecompanion").setup({
  memory = {
    opts = {
      chat = {
        default_params = "watch", -- watch|pin - when adding a buffer to the chat
      },
    },
  },
})
```

> [!NOTE]
> The `claude` parser has been specifically built to output linked files that take advantage of this.
