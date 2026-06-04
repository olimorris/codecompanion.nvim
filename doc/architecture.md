---
description: "How CodeCompanion manages LLM context windows, handles token limits, and is architected internally — reference for contributors and advanced users."
---

# Architecture

This section of the documentation covers architectural concepts and design principles that underpin CodeCompanion's functionality.

This is not mandatory reading for users of CodeCompanion. It may be of interest to those who are looking to understand some of the technical details of how CodeCompanion works, or those who are looking to contribute to the project.

## How Context Is Managed

One of the limitations of working with LLMs is that of context, as they have a finite window with which they can respond to a user's ask. That is, there's only a certain amount of data that LLMs can reference in order to generate a response. To equate this to human terms, it can be thought of as [working memory](https://en.wikipedia.org/wiki/Working_memory) and it varies greatly depending on what model you're using. The context window is measured in [tokens](https://platform.claude.com/docs/en/about-claude/glossary#tokens).

When a user breaches the context window, the conversation **ends** and it **cannot** continue. This can be hugely inconvenient in the middle of a coding session and potentially time consuming to recover from. CodeCompanion has context awareness which means it can prevent this from happening by taking **preventative** action and it does this in two ways:

1. **Context editing** - Whereby the conversation history is edited to remove less relevant information
2. **Compaction** - Where a conversation is summarised, removing historical messages and content

### In the Chat Buffer

Firstly, CodeCompanion manages context by paying close attention to the number of tokens in the [chat buffer](/usage/chat-buffer/), matching them against a defined trigger threshold in your config, which can be [customised](/configuration/chat-buffer#context-management).

CodeCompanion uses two thresholds: an **editing** trigger (default `0.65` of the context window) and a **compaction** trigger (default `0.85`). When the chat buffer crosses the lower threshold, context editing begins. If it later crosses the upper threshold then compaction runs. The lower threshold ensures that the lower risk editing action is triggered more often, buying more time before compaction is required.

#### Context Editing

> [!NOTE]
> Inspired by [Anthropic's context editing](https://platform.claude.com/docs/en/build-with-claude/context-editing)

Context editing is the lighter and more risk-free option of the two operations. It walks through the chat's message history and replaces the *content* of older tool call results with a placeholder, leaving the conversation intact. This ensures that tool calls and tool results are never orphaned, whilst ensuring the token count is reduced.

Editing works in terms of **cycles**. A cycle represents one user turn and everything the LLM did in response to it (tool calls, tool results, replies). By default, the most recent 3 cycles are preserved in full; older cycles have their tool results swapped for a placeholder. This means an in-flight agentic loop is never cut in half — a cycle is preserved or aged as a whole.

You can exclude specific tools from being edited via the `exclude_tools` configuration option. For example, the `memory` tool is excluded by default, since its output is often referenced again later in the conversation.

When a tool result is edited, its content becomes:

```
<important>Tool result cleared to save context. Re-run the tool if you need this output</important>
```

#### Compaction

> [!NOTE]
> Inspired by [Claude Code's compaction prompt](https://github.com/Piebald-AI/claude-code-system-prompts)

When no more editing can be performed, CodeCompanion will use compaction. It makes a single LLM call to summarise the conversation so far, then replaces the message history with that summary.

Not everything in the history is summarised and the below items are preserved:

- The system prompt
- Project rules (anything tagged via the [`/rules`](/usage/chat-buffer/slash-commands#rules) slash command)

Files, buffers, and images that were attached during the chat are replaced with reference placeholders, similarly to how tool results are replaced when edited:

```
<important>File content for `lua/foo.lua` cleared during compaction. Re-read the file if you need it.</important>
```

The placeholder names the file so the LLM knows how to re-read or re-request it. All other messages are summarised and removed.

Compaction can use a different adapter than the chat itself, which is useful if you want a cheaper or faster model handling the summary. You can also choose to fall back to the chat adapter if the override fails — by default, a failure simply skips that round and notifies you.

The summary is appended to the chat as a new user message and tagged so future compactions can identify and replace it. The chat is automatically submitted so the LLM has a chance to respond to the summarised context and restart the agentic loop.

#### Server-Side Compaction

If you're using the `openai_responses` or `anthropic` adapters, then CodeCompanion will use their native server-side compaction capabilities. Please see the [OpenAI compaction documentation](https://developers.openai.com/api/docs/guides/compaction) and [Anthropic compaction documentation](https://platform.claude.com/docs/en/build-with-claude/compaction) for more information. Editing still runs client-side for these adapters since it produces tokens-over-the-wire savings independent of what the server does.

#### Manual Triggers

Compaction can also be triggered manually via the [`/compact`](/usage/chat-buffer/slash-commands#compact) slash command, regardless of where the token count sits. Editing has no manual equivalent — it runs automatically when the threshold is crossed.
