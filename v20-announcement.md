Title: New in v20.0.0 - ✨ Inline interaction, `edit_file` tool and new adapter defaults

Dear All,

#3437 sees CodeCompanion bump to `v20.0.0`. There are breaking changes in this release, so be sure to read the upgrade guide before updating.

> [!IMPORTANT]
> Keep your plugins pinned to `^19.0.0` to avoid these breaking changes. CodeCompanion now requires Neovim 0.12 or later

## Breaking Changes

As always, the [upgrade guide](https://codecompanion.olimorris.dev/configuration/upgrading#v19-27-0-to-v20-0-0) covers everything in full. The key notes are:

- The `openai` adapter now uses OpenAI's [Responses API](https://platform.openai.com/docs/api-reference/responses) and `gemini` uses Google's [Interactions API](https://ai.google.dev/gemini-api/docs/interactions). The previous adapters live on as `openai_legacy` and `gemini_legacy`, and `openai_responses` and `gemini_interactions` have been removed
- The GitHub Models adapter has been removed
- The `insert_edit_into_file` tool is now `edit_file`. It takes the same options so it's a simple rename in your config, groups and prompts
- `web_search` now defaults to DuckDuckGo and `fetch_webpage` and `/fetch` default to [MarkItDown](https://github.com/microsoft/markitdown). as flagged in the `v19.24.0` announcement. MarkItDown needs to be installed locally and `:checkhealth codecompanion` will tell you if it's missing
- `auto_submit_errors` and `auto_submit_success` have been removed. A tool's output is now always sent back to the LLM as part of the [agent loop](https://codecompanion.olimorris.dev/usage/chat-buffer/agents-tools#how-they-work)
- The `/image` slash command has been removed. Use `/file` or the new `/file-from-url` instead
- Chat buffer methods (like `add_tool_output` and `add_context`) and HTTP adapter handlers now take a table rather than positional arguments. This only affects you if you've written your own tools, slash commands or adapters
- The inline interaction has been rewritten (see below). If you've customised it, there's a dedicated section in the upgrade guide

## What's New

### `edit_file` tool (#3427)

The `insert_edit_into_file` tool has served CodeCompanion well for the last 12 months or so. It was the first time I had confidence that CodeCompanion could edit files as well as agents in the CLI. Alas, it wasn't perfect, particularly with the smaller, self-hosted models that a lot of you use.

So I did plenty of research into the best way forward and ultimately landed on Claude Code's approach of editing a file by exact string replacement. If the text isn't found, or matches more than once, the tool returns an error and the LLM tries again, rather than the tool guessing with fuzzy matching. The tool's description is also around 650 characters instead of 8,700, which cuts the cost of every request.

A key requirement was that it had to be more accurate, faster and cheaper. Across 24 models and 14 scenarios via the [tool-testing harness](https://github.com/olimorris/codecompanion.nvim/tree/main/tests/scripts/tool_testing):

| Metric                             | `insert_edit_into_file` | `edit_file`      |
|------------------------------------|-------------------------|------------------|
| Pass rate (all 24 models)          | 72.6%                   | **91.4%**        |
| Pass rate (excl. self-host models) | 86.5%                   | **99.2%**        |
| Mean tokens per run                | 5,215                   | **2,389** (-54%) |
| Median duration                    | 6.8s                    | **5.9s** (-13%)  |

Huge shoutout to @ElliottLester and @bassamsdata who helped to drive this one on.

### Inline Interaction (#3437)

https://github.com/user-attachments/assets/dcddcb85-cba0-4017-9723-6e6b7f080fee

The inline interaction has been rebuilt from the ground up. Rather than asking the LLM where to place a block of code, it now shares the buffer and edits it with the `edit_file` tool, using the same adapter logic as the chat buffer. This means multiple edits can be made to a single buffer, in one go, and with far greater accuracy.

Some highlights:

- Review edits a hunk at a time with `ga` (accept), `gr` (reject) and `u` (undo), moving between hunks with `}` and `{`
- Make a visual selection and the LLM can only edit those lines, whilst still seeing the rest of the buffer
- Ask a question rather than for a change and the reply opens in a float
- `:CodeCompanion` on its own opens a new input box. Press `ga` to change the adapter and model (remembered per buffer) and `<Up>` to [continue the last conversation](https://codecompanion.olimorris.dev/usage/inline#continuing-a-conversation)
- ACP agents like Claude Code and Codex now work with inline too

> [!NOTE]
> Editing via a tool needs a capable model, so the default inline adapter is now `copilot` with `gpt-5.4-mini`. If you're on Copilot's free or student plan, you'll need to [change the adapter](https://codecompanion.olimorris.dev/configuration/inline#changing-adapter)

The [usage](https://codecompanion.olimorris.dev/usage/inline) part of the docs covers everything in full.

### OpenAI and Gemini Adapters (#3431)

I said back in `v17.26.0` that I expected providers to move to newer APIs and that's now happened. `openai` is now built on the Responses API and `gemini` on the Interactions API. If you've extended either of these in your config, you'll get the new APIs too. If you'd rather stay where you are, swap to `openai_legacy` or `gemini_legacy`.

### Prompt Library (#3450 | #3449)

The prompt library now plays nicely with non-coding prompts. Previously, the tool system prompt bundled coding guidance alongside instructions on how to use tools. They're now separate, so a prompt that replaces the chat system prompt no longer touches the tool instructions. User prompts can also be blank.

You can also reference the date via the `context` table in your prompts.

## Closing Thoughts

This release has been about making CodeCompanion's role as the harness more explicit (#3432) and tidying up decisions that didn't scale, such as positional arguments across the chat buffer and adapters. It means fewer breaking changes going forward when I add new features.

If you're facing any challenges with the upgrade, I'd advise opening up a new discussion - it makes it easier for other people to find.

Thanks and hope you enjoy this release!

Oli

<a href="https://www.buymeacoffee.com/olimorris" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="32" width="136"></a>
