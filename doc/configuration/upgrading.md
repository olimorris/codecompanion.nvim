---
description: "Step-by-step guide for upgrading CodeCompanion between major versions, covering breaking changes, configuration migration, and version pinning in Neovim."
---

# Upgrading CodeCompanion

This document provides a guide for upgrading from one version of CodeCompanion to another.

CodeCompanion follows [semantic versioning](https://semver.org/) and to avoid breaking changes, it is recommended to pin the plugin to a specific version in your Neovim configuration. The [installation guide](/installation) provides more information on how to do this.

## v19.27.0 to v20.0.0

> [!IMPORTANT]
> The `openai` and `gemini` adapters now use different APIs. If you use either of them, read the [Adapters](#adapters) section before upgrading

### Adapters

- `openai` now uses OpenAI's [Responses API](https://platform.openai.com/docs/api-reference/responses) and `gemini` uses Google's [Interactions API](https://ai.google.dev/gemini-api/docs/interactions). The previous adapters have been renamed to `openai_legacy` and `gemini_legacy`
- This includes `extend("openai")` and `extend("gemini")`, so any adapter you've built on them now uses the new APIs
- The `openai_responses` and `gemini_interactions` adapters have been removed. Use `openai` and `gemini` instead
- Update any references in your own plugins from `require("codecompanion.adapters.http.openai")` to `require("codecompanion.adapters.http.openai_legacy")`
- The GitHub Models adapter has been removed

To keep using the previous APIs:

::: code-group

```lua [Interactions]
require("codecompanion").setup({
  interactions = {
    chat = {
      adapter = "openai_legacy", -- Can be "openai_legacy" or "gemini_legacy"
    },
    inline = {
      adapter = "openai_legacy",
    },
  },
})
```

```lua [Extending]
require("codecompanion").setup({
  adapters = {
    http = {
      openai = function()
        return require("codecompanion.adapters").extend("openai_legacy", { -- [!code ++]
          env = {
            api_key = "OPENAI_API_KEY",
          },
        })
      end,
    },
  },
})
```

:::

- HTTP adapter handlers in the nested format (`lifecycle`, `request`, `response` and `tools`) now take a single `args` table after `self`, in place of positional arguments. New fields can then be added without breaking your handlers, and a handler that wraps another can pass `args` straight through. If you've written or extended an adapter in this format, update each handler:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      openai = function()
        return require("codecompanion.adapters").extend("openai", {
          handlers = {
            response = {
              parse_chat = function(self, data, tools) -- [!code --]
              parse_chat = function(self, args) -- [!code ++]
                local data, tools = args.data, args.tools -- [!code ++]
                -- ...
              end,
            },
          },
        })
      end,
    },
  },
})
```

The fields in `args` match the old positional arguments:

| Handler | `args` |
|---|---|
| `lifecycle.on_exit` | `data` |
| `request.build_parameters` | `params`, `messages` |
| `request.build_messages` | `messages` |
| `request.build_tools` | `tools` |
| `request.build_structured_output` | `schema` |
| `request.build_reasoning` | `data` |
| `request.build_body` | `payload` |
| `response.parse_chat` | `data`, `tools` |
| `response.parse_tokens` | `data` |
| `response.parse_meta` | `data` |
| `tools.format_calls` | `tools` |
| `tools.format_response` | `tool_call`, `output` |

`lifecycle.setup` and `lifecycle.teardown` still only take `self`. Adapters in the flat format, such as `form_messages` and `chat_output`, are unaffected.

- ACP adapters now use the same nested format, with `lifecycle.setup`, `lifecycle.auth`, `lifecycle.on_exit` and `request.build_messages`. Flat handlers still work, and take precedence over the nested ones when you extend an adapter. `helpers.form_messages` is now `helpers.build_messages`, though the old name still works:

```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      claude_code = function()
        return require("codecompanion.adapters").extend("claude_code", {
          handlers = {
            form_messages = function(self, messages, capabilities) -- [!code --]
            request = { -- [!code ++]
              build_messages = function(self, args) -- [!code ++]
                -- args.messages, args.capabilities
              end,
            }, -- [!code ++]
          },
        })
      end,
    },
  },
})
```

### Slash Commands

- The `/image` slash command has been removed. Select an image with [/file](/usage/chat-buffer/slash-commands#file) instead, or use the new [/file-from-url](/usage/chat-buffer/slash-commands#file-from-url) slash command for an image at a URL. If you set `opts.dirs` for `/image`, move it to `/file`. `opts.filetypes` and `opts.provider` have no equivalent and can be deleted:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      slash_commands = {
        ["image"] = { -- [!code --]
        ["file"] = { -- [!code ++]
          opts = {
            dirs = { "~/Pictures" },
          },
        },
      },
    },
  },
})
```

### Tools

- The `insert_edit_into_file` tool has been replaced by [edit_file](/usage/chat-buffer/agents-tools#edit-file) ([#3427](https://github.com/olimorris/codecompanion.nvim/pull/3427)). It takes the same options, so rename any references in your config, custom groups and prompts:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["insert_edit_into_file"] = { -- [!code --]
        ["edit_file"] = { -- [!code ++]
          opts = {
            require_confirmation_after = false,
          },
        },
      },
    },
  },
})
```

- The [web_search](/usage/chat-buffer/agents-tools#web-search) tool now uses DuckDuckGo by default, which doesn't need an API key. Previously it used Tavily
- The [fetch_webpage](/usage/chat-buffer/agents-tools#fetch-webpage) tool and [/fetch](/usage/chat-buffer/slash-commands#fetch) slash command now use [MarkItDown](https://github.com/microsoft/markitdown) by default. Previously they used Jina

> [!IMPORTANT]
> MarkItDown runs the `markitdown` CLI on your machine, so it must be installed. `:checkhealth codecompanion` will tell you if it's missing

To keep the previous defaults:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      slash_commands = {
        ["fetch"] = {
          opts = {
            adapter = "jina",
          },
        },
      },
      tools = {
        ["fetch_webpage"] = {
          opts = {
            adapter = "jina",
          },
        },
        ["web_search"] = {
          opts = {
            adapter = "tavily",
          },
        },
      },
    },
  },
})
```

- `interactions.chat.tools.opts.auto_submit_errors` and `interactions.chat.tools.opts.auto_submit_success` have been removed. A tool's output is now always sent back to the LLM, as part of the [agent loop](/usage/chat-buffer/agents-tools#how-they-work)

### Chat

Chat buffer methods that took several positional arguments now take a single table. If you call any of these from a custom tool, slash command or callback, you'll need to update them:

| Method | Before | After |
|--------|--------|-------|
| `add_tool_output` | `(tool, for_llm, for_user)` | `({ tool, for_llm, for_user? })` |
| `add_context` | `(data, source, id, opts)` | `(data, { source, id, bufnr?, path?, tag?, visible?, context_opts? })` |
| `change_adapter` | `(adapter, callback)` | `({ adapter, model?, callback? })` |
| `done` | `(output, reasoning, tools, meta, opts)` | `({ output?, reasoning?, tools?, meta?, status?, error? })` |
| `update_buf_line` | `(line_number, content, opts)` | `({ line_number, content, status?, icon_id?, priority?, virt_text_pos? })` |

For example, in a tool's output handler:

```lua
chat:add_tool_output(self, "The result is 42") -- [!code --]
chat:add_tool_output({ tool = self, for_llm = "The result is 42" }) -- [!code ++]
```

### Inline

The inline interaction now edits the buffer with the [edit_file](/usage/chat-buffer/agents-tools#edit-file) tool, rather than asking the LLM where to place a block of code. See [How Edits Work](/usage/inline#how-edits-work).

- The adapter's model must support tool calling. Inline prompts sent with an adapter that doesn't, such as `xai`, are refused with an error
- The current buffer is always shared with the LLM, up to a [context limit](/configuration/inline#context-limit). You no longer need `#{buffer}` in your inline prompts
- With a visual selection, the LLM can only edit the selected lines
- The `placement` prompt library option has been removed, along with the option to write code into a new buffer. Inline prompts that set `placement` can delete it
- `pre_hook` no longer runs for inline prompts
- `display.inline.layout` has been removed
- `:CodeCompanion` with no prompt, and prompts with `user_prompt`, now open CodeCompanion's input box rather than `vim.ui.input`
- The inline diff can be reviewed a hunk at a time with the new `accept_hunk` (`ga`) and `reject_hunk` (`gr`) keymaps in `interactions.shared.keymaps`. `reject_change` now rejects only the hunks that are left
- The `Unit tests` prompt (`/tests`) has been removed from the prompt library
- The `response.parse_inline` and `inline_output` adapter handlers have been removed. If your adapter defines either, delete it. Inline now uses `response.parse_chat` (or `chat_output`) and the tool handlers, the same as the chat buffer

## v18.7.0 to v19.0.0

- The Super Diff has now been removed from CodeCompanion ([#2600](https://github.com/olimorris/codecompanion.nvim/pull/2600))
- CodeCompanion now only supports a built-in diff which is enabled by default ([#2600](https://github.com/olimorris/codecompanion.nvim/pull/2600)), dropping support for Mini.Diff
- The `full_stack_dev` group has been renamed to [agent](/usage/chat-buffer/agents-tools#agent) ([#2786](https://github.com/olimorris/codecompanion.nvim/pull/2786))
- The `next_edit_suggestion` and `list_code_usages` tools have been removed

### Adapters

- For the Claude Code adapter to work, you'll need to ensure you have Zed's [claude-agent-acp](https://github.com/zed-industries/claude-agent-acp) adapter installed. This has been renamed from _claude-code-acp_ in recent weeks ([#2779](https://github.com/olimorris/codecompanion.nvim/pull/2779))

### Config

- Diff keymaps have moved from `interactions.inline.keymaps` to `interactions.shared.keymaps` ([#2600](https://github.com/olimorris/codecompanion.nvim/pull/2600))
- All diff config has moved to `display.diff` ([#2600](https://github.com/olimorris/codecompanion.nvim/pull/2600))
- `variables` have been renamed to `editor_context` and the config paths are now `interactions.chat.editor_context` and `interactions.inline.editor_context` ([#2719](https://github.com/olimorris/codecompanion.nvim/pull/2719))
- Across _editor context_, _slash commands_ and _tools_, `callback` has been replaced by `path` for string values (module paths and file paths). `callback` is still used for function values, however

### Prompt Library

- The location of rules within a prompt library item has changed from `opts.rules` to `rules`:

```markdown
---
name: Oli's test workflow
strategy: chat
description: Workflow test prompt
rules:
  - test_rule
---
```

## v17.33.0 to v18.0.0

### Config

- The biggest change in this release is the renaming of `strategies` to `interactions`. This will only be a breaking change if you specifically reference `codecompanion.strategies` in your configuration. If you do, you'll need to change it to `codecompanion.interactions` ([#2485](https://github.com/olimorris/codecompanion.nvim/pull/2485))
- Previously, built-in slash commands and tools were stored in `/catalog` folders which have now been renamed to `/builtin`. If you reference these in your configuration you'll need to update the paths accordingly ([#2482](https://github.com/olimorris/codecompanion.nvim/pull/2482))
- Workspaces have now been removed from the plugin. Please use [Rules](/configuration/rules) instead.

### Adapters

- If you have a custom adapter, you'll need to rename `condition` to be `enabled` on any schema items ([#2439](https://github.com/olimorris/codecompanion.nvim/pull/2439/commits/cb14c7bac869346e2d12b775c4bf258606add569)):

```lua
return {
  schema = {
    ["reasoning.effort"] = {
      ---@type fun(self: CodeCompanion.HTTPAdapter): boolean
      condition = function(self) -- [!code --]
      enabled = function(self) -- [!code ++]
        --
      end,
    },
  }
}
```

- The default adapters on the **Anthropic** and **Gemini** adapters have changed to `claude-sonnet-4-5-20250929` and `gemini-3-pro-preview`, respectively ([#2494](https://github.com/olimorris/codecompanion.nvim/pull/2494))
- If you wish to hide the adapters that come with CodeCompanion, `adapters.[acp|http].opts.show_defaults` has been renamed to `adapters.[acp|http].opts.show_presets` for both HTTP and ACP adapters ([#2497](https://github.com/olimorris/codecompanion.nvim/pull/2497))

### Chat

- Memory has been renamed to rules. Please rename any references to `memory` in your configuration to `rules`. Please refer to the [Rules](/configuration/rules) documentation for more information ([#2440](https://github.com/olimorris/codecompanion.nvim/pull/2440))
- `default_memory` has been renamed to `autoload` ([#2509](https://github.com/olimorris/codecompanion.nvim/pull/2509))
---
- The variable and parameter `#{buffer}{watch}` has been renamed to `#{buffer}{diff}`. This better reflects that an LLM receives a diff of buffer changes with each request ([#2444](https://github.com/olimorris/codecompanion.nvim/pull/2444))
- The variable and parameter `#{buffer}{pin}` has now been renamed to `#{buffer}{all}`. This better reflects that the
  entire buffer is sent to the LLM with each request ([#2444](https://github.com/olimorris/codecompanion.nvim/pull/2444))
---
- Passing an adapter as an argument to `:CodeCompanionChat` is now done with `:CodeCompanionChat adapter=<adapter_name>` ([#2437](https://github.com/olimorris/codecompanion.nvim/pull/2437))
- If your chat buffer system prompt is still stored at `opts.system_prompt` you'll need to change it to `interactions.chat.opts.system_prompt` ([#2484](https://github.com/olimorris/codecompanion.nvim/pull/2484))

### Prompt Library

If you have any prompts defined in your config, you'll need to:

- Rename `opts.short_name` to `opts.alias` for each item in order to allow you to call them with `require("codecompanion").prompt("my_prompt")` or as slash commands in the chat buffer ([#2471](https://github.com/olimorris/codecompanion.nvim/pull/2471)).

```lua
["my custom prompt"] = {
  strategy = "chat",
  description = "My custom prompt",
  opts = {
    short_name = "my_prompt", -- [!code --]
    alias = "my_prompt", -- [!code ++]
  },
  prompts = {
    -- ...
  },
},
```

- Change all workflow prompts, replacing `strategy = "workflow"` with `interaction = "chat"` and specifying `opts.is_workflow = true` ([#2487](https://github.com/olimorris/codecompanion.nvim/pull/2487)).

```lua
["my_workflow"] = {
  strategy = "workflow", -- [!code --]
  interaction = "chat", -- [!code ++]
  description = "My custom workflow",
  opts = {
    is_workflow = true, -- [!code ++]
  },
  prompts = {
    -- ...
  },
},
```

- If you don't wish to display any of the built-in prompt library items, you'll need to change `display.action_palette.show_default_prompt_library` to `display.action_palette.show_preset_prompts` ([#2499](https://github.com/olimorris/codecompanion.nvim/pull/2499))

### Tools

If you have any tools in your config, you'll need to rename:

- `requires_approval` to `require_approval_before` ([#2439](https://github.com/olimorris/codecompanion.nvim/pull/2439/commits/cb14c7bac869346e2d12b775c4bf258606add569))
- `user_confirmation` to `require_confirmation_after` ([#2450](https://github.com/olimorris/codecompanion.nvim/pull/2450))

These now better reflect the timing of each action.

### UI

- The `display.chat.child_window` has been renamed `display.chat.floating_window` to better describe what it is ([#2452](https://github.com/olimorris/codecompanion.nvim/pull/2452))
- The `display.action_palette.opts.show_default_actions` has been renamed to be `display.action_palette.opts.show_preset_actions` ([#2499](https://github.com/olimorris/codecompanion.nvim/pull/2499))
