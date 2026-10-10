---
description: "Understand how CodeCompanion keeps a conversation inside the LLM's context window, for contributors and curious users."
---

# Architecture

This page covers how parts of CodeCompanion work under the hood. You don't need it to use the plugin, but it's useful if you're contributing or want to know why CodeCompanion behaves the way it does.

## How Context Is Managed

An LLM can only consider a limited number of [tokens](https://platform.claude.com/docs/en/about-claude/glossary#tokens) at once, known as its _context window_. When a conversation outgrows it, the conversation ends and can't continue, which is costly in the middle of a coding session.

CodeCompanion acts before that happens, in two ways:

- **Context editing** - Clears older tool results from the message history
- **Compaction** - Summarises the conversation and replaces the message history with the summary

Both apply to HTTP adapters only. ACP agents manage their own context.

### In the Chat Buffer

CodeCompanion counts the tokens in the [chat buffer](/usage/chat-buffer/) after each response, and before tool output is sent back, then compares them with two [thresholds](/configuration/context-management):

| Operation | Default trigger |
|---|---|
| Context editing | `0.65` of the context window |
| Compaction | `0.85` of the context window |

The lower threshold means the cheaper, lower risk editing runs first and more often, which delays the need for compaction. Once the conversation crosses the upper threshold, compaction runs instead.

### Context Editing

> [!NOTE]
> Inspired by [Anthropic's context editing](https://platform.claude.com/docs/en/build-with-claude/context-editing)

Context editing replaces the _content_ of older tool results with a placeholder, leaving the conversation's shape intact. Tool calls and their results are never orphaned, and the token count drops:

```
<important>Tool result cleared to save context. Re-run the tool if you need this output</important>
```

Editing works in _cycles_. A cycle is one user turn and everything the LLM did in response, such as tool calls, tool results and replies. The last three cycles are kept in full, as set by `keep_cycles`, and older cycles have their tool results cleared. An in-flight [agent loop](/usage/chat-buffer/agents-tools#how-they-work) is never cut in half, as a cycle is kept or cleared as a whole.

Output from the tools in `exclude_tools` is never cleared. By default that's the `memory` tool, as its output is often referenced later in the conversation.

### Compaction

> [!NOTE]
> Inspired by [Claude Code's compaction prompt](https://github.com/Piebald-AI/claude-code-system-prompts)

Compaction makes one LLM request to summarise the conversation so far, then replaces the message history with that summary. These are kept as they are:

- The system prompt
- [Rules](/usage/chat-buffer/rules)

A summary from an earlier compaction isn't kept. The new summary replaces it.

Files, buffers and images are replaced with a placeholder that names the source, so the LLM knows what to re-read or ask for:

```
<important>File content for `lua/codecompanion/init.lua` cleared during compaction. Re-read the file if you need it.</important>
```

Everything else is summarised and removed. Compaction is skipped if it would save fewer than 10,000 tokens, as set by `min_token_savings`.

The summary is added to the chat as a new user message, and the chat is submitted so the LLM can carry on from where it left off.

Compaction can use a cheaper or faster adapter than the chat itself. If that adapter fails, the round is skipped and the error is logged, unless you've set `fallback_to_chat_adapter`, in which case it retries with the chat's adapter. See [Configuring Context Management](/configuration/context-management) for both options.

### Server-Side Compaction

For models that support it, the `anthropic` and `openai` adapters hand context management to the provider and CodeCompanion's own editing and compaction are turned off:

| Adapter | Server-side features |
|---|---|
| `anthropic` | [Context editing](https://platform.claude.com/docs/en/build-with-claude/context-editing) and [compaction](https://platform.claude.com/docs/en/build-with-claude/compaction) |
| `openai` | [Compaction](https://developers.openai.com/api/docs/guides/compaction) |

Both use your thresholds, but the compaction trigger is never set below 50,000 tokens. To keep CodeCompanion in charge, see [Disabling Compaction](/configuration/adapters-http#disabling-compaction).

### Manual Triggers

The [/compact](/usage/chat-buffer/slash-commands#compact) slash command compacts the conversation straight away, wherever the token count sits, and ignores `min_token_savings`. Editing has no manual equivalent.
