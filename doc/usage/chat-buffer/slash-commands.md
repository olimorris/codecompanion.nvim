---
description: "Add files, buffers, URLs, help tags and symbols to the chat buffer, and manage sessions, MCP servers and ACP agents, with slash commands."
---

# Using Slash Commands

<p>
  <img src="https://github.com/user-attachments/assets/02b4d5e2-3b40-4044-8a85-ccd6dfa6d271" alt="Using slash commands" />
</p>

Slash commands add context to the chat buffer and act on the chat itself. Type `/` in the chat buffer to list them. They come from the `interactions.chat.slash_commands` table, plus any [prompt library](/configuration/prompt-library#options) item with `opts.is_slash_cmd = true`, such as the built-in `/commit` and `/explain`.

> [!NOTE]
> An [ACP](/configuration/adapters-acp) agent such as Claude Code has its own commands, which are triggered with `\` to keep them apart. See [completion](/usage/chat-buffer/#completion)

| Command | Description |
| --- | --- |
| [/acp_session_options](#acp-session-options) | Change an ACP agent's session config options |
| [/buffer](#buffer) | Add open buffers |
| [/command](#command) | Change the command used to start an ACP agent |
| [/compact](#compact) | Replace the message history with a summary |
| [/fetch](#fetch) | Add the contents of a URL |
| [/file](#file) | Add files, images or PDFs |
| [/file-from-url](#file-from-url) | Download a file and add it |
| [/fork](#fork) | Copy the chat into a new chat buffer |
| [/help](#help) | Add content from Vim help tags |
| [/mcp](#mcp) | Start and stop MCP servers |
| [/mcp-prompts](#mcp-prompts) | Add a prompt from an MCP server |
| [/now](#now) | Insert the current date and time |
| [/rename](#rename) | Rename the chat |
| [/resume](#resume) | Restore a previous session |
| [/rules](#rules) | Add a rules group |
| [/save](#save) | Save the chat as a session |
| [/share](#share) | Share the chat as a GitHub Gist |
| [/skills](#skills) | Add skills |
| [/skills-group](#skills-group) | Add a group of skills |
| [/symbols](#symbols) | Add a symbolic outline of a file |

Some commands only appear for one type of adapter. The section for each command says which.

## /acp_session_options

> [!NOTE]
> ACP adapters only

The _acp_session_options_ slash command changes an agent's [session config options](https://agentclientprotocol.com/protocol/session-config-options), such as its mode or reasoning level.

## /buffer

<p>
<img src="https://github.com/user-attachments/assets/1be7593b-f77f-44f9-a418-1d04b3f46785" alt="buffer slash command" />
</p>

The _buffer_ slash command adds the contents of one or more open buffers to the chat buffer. It works with the default picker, Telescope, fzf-lua, mini.pick and Snacks.

By default, an added buffer is [synced](/configuration/chat-buffer#syncing) by its diff, so the LLM sees your changes on every turn. Set `opts.default_params` to `"all"` to send the whole buffer instead.

In the [CLI prompt input](/usage/cli#slash-commands), this command inserts `@path` references instead of buffer contents.

## /command

> [!NOTE]
> ACP adapters only

The _command_ slash command switches the command used to start an ACP agent, such as one that runs the agent with a specific flag. **Switching commands resets the conversation with the agent**.

## /compact

> [!NOTE]
> HTTP adapters only

The _compact_ slash command replaces the chat's message history with a summary, based on [Claude Code's](https://code.claude.com/docs/en/slash-commands#built-in-slash-commands) feature of the same name. You confirm before the summary is generated.

The system prompt and rules are kept. Files, buffers and images are replaced with placeholders naming each one, and everything else is summarised. See [compaction](/architecture#compaction) for the details.

## /fetch

> [!TIP]
> To understand a Neovim plugin better, send its `config.lua` to your LLM with `/fetch` alongside your prompt

The _fetch_ slash command adds the contents of a URL to the chat buffer. By default, the [MarkItDown](https://github.com/microsoft/markitdown) CLI converts the page into Markdown, and also handles local files and documents such as PDF and DOCX. The [Jina](https://jina.ai) adapter is an alternative that needs nothing installed locally:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      slash_commands = {
        ["fetch"] = {
          opts = {
            adapter = "jina", -- Can be "markitdown" or "jina"
          },
        },
      },
    },
  },
})
```

After a fetch, you're asked whether to cache the page. Once anything is cached, `/fetch` asks whether to enter a URL or pick from the cache.

MarkItDown times out after two minutes. To change this:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      extend = {
        markitdown = {
          opts = {
            timeout = 300000, -- milliseconds
          },
        },
      },
    },
  },
})
```

## /file

<p>
  <video controls muted title="File slash command demo" src="https://github.com/user-attachments/assets/3359c752-e5e0-41bf-8952-557edf11efdf"></video>
</p>

The _file_ slash command adds the contents of one or more files in the current working directory to the chat buffer. It works with the default picker, Telescope, fzf-lua, mini.pick and Snacks. In most pickers, `<CR>` selects a file and `<Tab>` marks several.

[Context formatters](/configuration/chat-buffer#context-formatters) can reshape a file's content before the LLM sees it.

In the [CLI prompt input](/usage/cli#slash-commands), this command inserts `@path` references instead of file contents.

**Searching Other Directories**

To search other directories alongside the current working directory:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      slash_commands = {
        ["file"] = {
          opts = {
            dirs = { "~/notes", "../shared-library" },
          },
        },
      },
    },
  },
})
```

Paths can be relative or start with `~`.

**Images**

A GIF, JPEG, PNG or WebP image is sent to the LLM as an image rather than as file content. If the adapter doesn't support vision, the image isn't added.

**PDFs**

A PDF is base64 encoded and sent to the LLM as a document ([#3218](https://github.com/olimorris/codecompanion.nvim/pull/3218)). If the adapter doesn't support documents, the PDF isn't added. These HTTP adapters support them:

- Anthropic
- Copilot, with OpenAI models only
- Gemini
- OpenAI
- OpenAI (Legacy)
- OpenRouter

## /file-from-url

The _file-from-url_ slash command downloads a file and adds it to the chat buffer, in the same way as [/file](#file). Images and PDFs are sent as attachments and anything else as file content, with the URL shown in place of the file path. A webpage is handed to [/fetch](#fetch) instead.

## /fork

> [!NOTE]
> HTTP adapters only

The _fork_ slash command copies the chat into a new chat buffer, keeping the message history, tools and context. Use it to branch a conversation and try different prompts, models or adapters without losing the original. You're asked for a title, which defaults to the current one.

To save every fork as a [session](/configuration/sessions) as soon as it's created:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      slash_commands = {
        ["fork"] = {
          opts = {
            auto_save_session = true,
          },
        },
      },
    },
  },
})
```

## /help

The _help_ slash command searches Vim help tags (`:h helpfile`) and adds the matching help content to the chat buffer. It works with Telescope, fzf-lua, mini.pick and Snacks, but not the default picker.

If a help file is longer than `opts.max_lines` (128 by default), you're asked whether to trim it to that many lines around the tag.

## /mcp

The _mcp_ slash command starts and stops [MCP](/configuration/mcp) servers. **This applies globally, so starting or stopping a server affects every chat buffer**. It works with `vim.ui.select` and Snacks.

## /mcp-prompts

The _mcp-prompts_ slash command adds a [prompt](https://modelcontextprotocol.io/specification/2025-11-25/server/prompts) from a running MCP server to the chat buffer, ready for you to edit before sending. After you select a prompt, you're asked for each of its arguments in turn. Optional arguments can be left blank, and cancelling at any point adds nothing.

> [!NOTE]
> Only the text from a prompt's `user` messages is added. Images, resources and `assistant` messages are skipped

## /now

The _now_ slash command inserts the current date and time into the chat buffer.

## /rename

> [!NOTE]
> HTTP adapters only

The _rename_ slash command changes the chat's title, which helps you tell chats apart in the [action palette](/usage/action-palette).

## /resume

The _resume_ slash command lists your past sessions and restores the selected one into a chat buffer. What it lists depends on the adapter:

- **HTTP** - The [sessions](/configuration/sessions) saved to disk. If the current chat has no messages, it's replaced by the restored one
- **ACP** - The agent's own sessions, if it supports the `session/list` and `session/load` capabilities

> [!NOTE]
> On an ACP adapter, `/resume` only works before you've sent a message

## /rules

The _rules_ slash command adds a [rules](/usage/chat-buffer/rules) group to the chat buffer. It's also available in the [CLI prompt input](/usage/cli#slash-commands).

## /save

> [!NOTE]
> HTTP adapters only, and hidden when sessions are disabled

The _save_ slash command saves the chat to disk as a [session](/configuration/sessions), which you can restore later with [/resume](#resume). You're asked for a title if the chat doesn't have one.

By default, a chat isn't saved until you use `/save`. After that, it's saved again after every response. Turn on `autosave` in the [session config](/configuration/sessions) to save every chat automatically.

## /share

The _share_ slash command shares the chat as a secret [GitHub Gist](https://gist.github.com) and copies its URL to the clipboard. It needs a GitHub token with the `gist` scope:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      slash_commands = {
        ["share"] = {
          opts = {
            token = os.getenv("GITHUB_GIST_TOKEN"),
          },
        },
      },
    },
  },
})
```

## /skills

The _skills_ slash command adds [skills](/usage/chat-buffer/skills) to the chat buffer. Depending on your picker, several can be selected at once.

## /skills-group

The _skills-group_ slash command adds a [group](/configuration/skills#groups) of skills in one go. It's hidden if you haven't configured any groups.

## /symbols

> [!NOTE]
> If a filetype isn't supported, consider a PR adding the Tree-sitter queries from [aerial.nvim](https://github.com/stevearc/aerial.nvim)

The _symbols_ slash command uses Tree-sitter to build a symbolic outline of a file, sharing its structure with the LLM for fewer tokens than the full content. The queries come from aerial.nvim, and the supported filetypes are listed in the [queries directory](https://github.com/olimorris/codecompanion.nvim/tree/main/queries).

It works with the default picker, Telescope, fzf-lua, mini.pick and Snacks, and several files can be selected at once.
