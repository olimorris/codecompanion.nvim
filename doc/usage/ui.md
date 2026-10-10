---
description: "Style CodeCompanion's highlight groups and read chat metadata to build your own statusline."
---

# Using the UI

<p>
  <video muted controls loop title="CodeCompanion UI customization demo" src="https://github.com/user-attachments/assets/a37180a0-0f1b-4ffb-8fae-44669e9d3df7"></video>
</p>

CodeCompanion changes as little of your UI as it can. Instead, it exposes chat metadata, highlight groups and [events](/usage/events) for you to build on. See [Extending the UI](/extending/ui) for examples.

## Metadata

`_G.codecompanion_chat_metadata` holds the state of every open chat buffer, keyed by buffer number:

| Key | Description |
| --- | --- |
| `adapter` | The adapter's `name`, `model`, `model_info` and `type` |
| `config_options` | The agent's configuration options, for ACP adapters |
| `context_items` | Number of context items in the chat |
| `cycles` | Number of turns, from your message to the LLM's response |
| `id` | The chat's ID |
| `tokens` | Running total of tokens |
| `tools` | Number of tools in the chat |

`_G.codecompanion_current_context` holds the number of the buffer that `#{buffer}` points at.

The video at the top of this page shows the metadata in a statusline.

## Highlight Groups

Every group links to a built-in group by default, so your colourscheme styles it until you override it.

**Chat buffer**

| Group | Description |
| --- | --- |
| `CodeCompanionChatHeader` | Headers |
| `CodeCompanionChatSeparator` | Separators between headers |
| `CodeCompanionChatInfo` | Information messages |
| `CodeCompanionChatWarn` | Warning messages |
| `CodeCompanionChatError` | Error messages |
| `CodeCompanionChatSubtext` | Text under an information, warning or error message |
| `CodeCompanionChatTokens` | Virtual text showing the token count |
| `CodeCompanionChatFold` | Folds, except for tool output |
| `CodeCompanionChatEditorContext` | Editor context, such as `#{buffer}` |
| `CodeCompanionChatTool` | Tools, such as `@{agent}` |
| `CodeCompanionChatToolText` | Tool output, overriding markdown rendering |
| `CodeCompanionChatToolPending` | A tool waiting to run |
| `CodeCompanionChatToolInProgress` | A running tool |
| `CodeCompanionChatToolSuccess` | The summary of a tool that succeeded |
| `CodeCompanionChatToolSuccessIcon` | The icon of a tool that succeeded |
| `CodeCompanionChatToolFailure` | The summary of a tool that failed |
| `CodeCompanionChatToolFailureIcon` | The icon of a tool that failed |

**Diffs**

| Group | Description |
| --- | --- |
| `CodeCompanionDiffAdd` | Added lines |
| `CodeCompanionDiffDelete` | Deleted lines |
| `CodeCompanionDiffText` | Added words within a changed line |
| `CodeCompanionDiffTextDelete` | Deleted words within a changed line |
| `CodeCompanionDiffBanner` | The keymap banner, aligned to the right of the window |
| `CodeCompanionDiffBannerInline` | The keymap banner, on its own line above the diff |

**Code reviews**

| Group | Description |
| --- | --- |
| `CodeCompanionCodeReviewHeader` | The round summary at the top of the review window |
| `CodeCompanionCodeReviewPath` | File paths in the checklist |
| `CodeCompanionCodeReviewAdded` | Added lines |
| `CodeCompanionCodeReviewRemoved` | Removed lines |
| `CodeCompanionCodeReviewComment` | Comments |
| `CodeCompanionCodeReviewSent` | Comments from the last review, shown above the changes that answer them |

**Other**

| Group | Description |
| --- | --- |
| `CodeCompanionCLIPath` | `@path` references in the CLI prompt input |
| `CodeCompanionVirtualText` | All other virtual text |
