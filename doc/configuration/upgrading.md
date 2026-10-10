---
description: "Update your config for the breaking changes in each major version of CodeCompanion."
---

# Upgrading CodeCompanion

CodeCompanion follows [semantic versioning](https://semver.org/), so breaking changes only arrive in a major version. Each section below lists what changed and how to update your config.

To upgrade when you're ready rather than when your plugin manager decides, pin CodeCompanion to a version. See the [installation guide](/installation).

## v19.27.0 to v20.0.0

> [!IMPORTANT]
> The `openai` and `gemini` adapters now use different APIs. If you use either of them, read the [Adapters](#adapters) section before upgrading

### Adapters

- `openai` now uses OpenAI's [Responses API](https://platform.openai.com/docs/api-reference/responses) and `gemini` uses Google's [Interactions API](https://ai.google.dev/gemini-api/docs/interactions). The previous adapters are now `openai_legacy` and `gemini_legacy`
- Adapters built with `extend("openai")` or `extend("gemini")` use the new APIs too
- `openai_responses` and `gemini_interactions` are removed. Use `openai` and `gemini` instead
- In your own plugins, change `require("codecompanion.adapters.http.openai")` to `require("codecompanion.adapters.http.openai_legacy")`
- The GitHub Models adapter is removed

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

- HTTP adapter handlers in the nested format (`lifecycle`, `request`, `response` and `tools`) now take a single `args` table after `self`, in place of positional arguments. New fields can be added without breaking your handlers, and a handler that wraps another can pass `args` straight through. If you've written or extended an adapter in this format, update each handler:

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
| --- | --- |
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

`lifecycle.setup` and `lifecycle.teardown` still take only `self`. Handlers in the flat format, such as `form_messages` and `chat_output`, are unaffected.

- ACP adapters now use the same nested format, with `lifecycle.setup`, `lifecycle.auth`, `lifecycle.on_exit` and `request.build_messages`. Flat handlers still work, and take precedence over nested ones when you extend an adapter. `helpers.form_messages` is now `helpers.build_messages`, though the old name still works:

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

- The `/image` slash command is removed. Select an image with [/file](/usage/chat-buffer/slash-commands#file), or use the new [/file-from-url](/usage/chat-buffer/slash-commands#file-from-url) slash command for an image at a URL. Move any `opts.dirs` you set for `/image` to `/file`, and delete `opts.filetypes` and `opts.provider`, which have no equivalent:

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

- The `insert_edit_into_file` tool is replaced by [edit_file](/usage/chat-buffer/agents-tools#edit-file) ([#3427](https://github.com/olimorris/codecompanion.nvim/pull/3427)). It takes the same options, so rename it in your config, custom groups and prompts:

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
> MarkItDown runs the `markitdown` CLI on your machine, so it must be installed. `:checkhealth codecompanion` reports if it's missing

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

- `interactions.chat.tools.opts.auto_submit_errors` and `interactions.chat.tools.opts.auto_submit_success` are removed. A tool's output is always sent back to the LLM, as part of the [agent loop](/usage/chat-buffer/agents-tools#how-they-work)

### Chat

Chat buffer methods that took several positional arguments now take a table. Update any calls from a custom tool, slash command or callback:

| Method | Before | After |
| --- | --- | --- |
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
- The current buffer is always shared with the LLM, up to a [context limit](/configuration/inline#context-limit), so the inline `#{buffer}` editor context has been removed. Delete it from your inline prompts
- With a visual selection, the LLM can only edit the selected lines
- Your `default` rules group, including `AGENTS.md` and `CLAUDE.md`, is sent with every inline prompt to an HTTP adapter, on top of the context limit. Set `rules.opts.inline.autoload = {}` to stop it. See [Rules and Skills](/configuration/inline#rules-and-skills)
- The `placement` prompt library option has been removed, along with the option to write code into a new buffer. Inline prompts that set `placement` can delete it
- `pre_hook` no longer runs for inline prompts
- A reply that doesn't edit the buffer, such as an answer to a question, opens in a float rather than a chat buffer
- `display.inline.layout` has been removed
- `:CodeCompanion` with no prompt, and prompts with `user_prompt`, now open CodeCompanion's input box rather than `vim.ui.input`
- The inline diff can be reviewed a hunk at a time with the new `accept_hunk` (`ga`), `reject_hunk` (`gr`) and `undo_hunk` (`u`) keymaps in `interactions.shared.keymaps`. `reject_change` now rejects only the hunks that are left
- The `Unit tests` prompt (`/tests`) has been removed from the prompt library
- The `response.parse_inline` and `inline_output` adapter handlers have been removed. If your adapter defines either, delete it. Inline now uses `response.parse_chat` (or `chat_output`) and the tool handlers, the same as the chat buffer

## v18.7.0 to v19.0.0

- The Super Diff is removed ([#2600](https://github.com/olimorris/codecompanion.nvim/pull/2600))
- CodeCompanion only supports its built-in diff, which is enabled by default. Mini.Diff is no longer supported ([#2600](https://github.com/olimorris/codecompanion.nvim/pull/2600))
- The `full_stack_dev` group is renamed to [agent](/usage/chat-buffer/agents-tools#agent) ([#2786](https://github.com/olimorris/codecompanion.nvim/pull/2786))
- The `next_edit_suggestion` and `list_code_usages` tools are removed

### Adapters

- The Claude Code adapter needs Zed's [claude-agent-acp](https://github.com/zed-industries/claude-agent-acp) installed, which was previously named _claude-code-acp_ ([#2779](https://github.com/olimorris/codecompanion.nvim/pull/2779))

### Config

- Diff keymaps have moved from `interactions.inline.keymaps` to `interactions.shared.keymaps` ([#2600](https://github.com/olimorris/codecompanion.nvim/pull/2600))
- All diff config has moved to `display.diff` ([#2600](https://github.com/olimorris/codecompanion.nvim/pull/2600))
- `variables` are renamed to `editor_context`, at `interactions.chat.editor_context` and `interactions.inline.editor_context` ([#2719](https://github.com/olimorris/codecompanion.nvim/pull/2719))
- Across editor context, slash commands and tools, string values for `callback` (module paths and file paths) move to `path`. `callback` is still used for functions

### Prompt Library

- Rules in a prompt library item move from `opts.rules` to `rules`:

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

- `strategies` is renamed to `interactions`. This only breaks your config if it references `codecompanion.strategies`, which becomes `codecompanion.interactions` ([#2485](https://github.com/olimorris/codecompanion.nvim/pull/2485))
- The `/catalog` folders for built-in slash commands and tools are renamed to `/builtin`. Update any paths in your config that point at them ([#2482](https://github.com/olimorris/codecompanion.nvim/pull/2482))
- Workspaces are removed. Use [rules](/configuration/rules) instead

### Adapters

- In a custom adapter, rename `condition` to `enabled` on any schema items ([#2439](https://github.com/olimorris/codecompanion.nvim/pull/2439/commits/cb14c7bac869346e2d12b775c4bf258606add569)):

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

- The default models for the `anthropic` and `gemini` adapters are now `claude-sonnet-4-5-20250929` and `gemini-3-pro-preview` ([#2494](https://github.com/olimorris/codecompanion.nvim/pull/2494))
- To hide the adapters that come with CodeCompanion, `adapters.[acp|http].opts.show_defaults` is renamed to `adapters.[acp|http].opts.show_presets` ([#2497](https://github.com/olimorris/codecompanion.nvim/pull/2497))

### Chat

- Memory is renamed to [rules](/configuration/rules). Rename any `memory` references in your config to `rules` ([#2440](https://github.com/olimorris/codecompanion.nvim/pull/2440))
- `default_memory` is renamed to `autoload` ([#2509](https://github.com/olimorris/codecompanion.nvim/pull/2509))
- `#{buffer}{watch}` is renamed to `#{buffer}{diff}`, as the LLM receives a diff of the buffer's changes with each request ([#2444](https://github.com/olimorris/codecompanion.nvim/pull/2444))
- `#{buffer}{pin}` is renamed to `#{buffer}{all}`, as the entire buffer is sent with each request ([#2444](https://github.com/olimorris/codecompanion.nvim/pull/2444))
- To pass an adapter to `:CodeCompanionChat`, use `:CodeCompanionChat adapter=<adapter_name>` ([#2437](https://github.com/olimorris/codecompanion.nvim/pull/2437))
- A chat system prompt at `opts.system_prompt` moves to `interactions.chat.opts.system_prompt` ([#2484](https://github.com/olimorris/codecompanion.nvim/pull/2484))

### Prompt Library

If you define prompts in your config:

- Rename `opts.short_name` to `opts.alias` on each item, so you can still call it with `require("codecompanion").prompt("my_prompt")` or as a slash command in the chat buffer ([#2471](https://github.com/olimorris/codecompanion.nvim/pull/2471)):

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

- In workflow prompts, replace `strategy = "workflow"` with `interaction = "chat"` and set `opts.is_workflow = true` ([#2487](https://github.com/olimorris/codecompanion.nvim/pull/2487)):

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

- To hide the built-in prompt library items, `display.action_palette.show_default_prompt_library` is renamed to `display.action_palette.show_preset_prompts` ([#2499](https://github.com/olimorris/codecompanion.nvim/pull/2499))

### Tools

If you configure tools, rename:

- `requires_approval` to `require_approval_before` ([#2439](https://github.com/olimorris/codecompanion.nvim/pull/2439/commits/cb14c7bac869346e2d12b775c4bf258606add569))
- `user_confirmation` to `require_confirmation_after` ([#2450](https://github.com/olimorris/codecompanion.nvim/pull/2450))

### UI

- `display.chat.child_window` is renamed to `display.chat.floating_window` ([#2452](https://github.com/olimorris/codecompanion.nvim/pull/2452))
- `display.action_palette.opts.show_default_actions` is renamed to `display.action_palette.opts.show_preset_actions` ([#2499](https://github.com/olimorris/codecompanion.nvim/pull/2499))
