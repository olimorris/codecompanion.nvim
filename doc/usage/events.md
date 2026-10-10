---
description: "Every event CodeCompanion fires, and how to hook into them from your Neovim config."
---

# Events

CodeCompanion fires `User` autocmds at points in its lifecycle, so your config can react to a chat opening, a request finishing or a file being edited.

For hooks that can change a chat's state, such as `on_before_submit` and `on_tool_output`, see [Callbacks](/configuration/callbacks).

## Consuming an Event

To format a buffer once an inline request finishes:

```lua
local group = vim.api.nvim_create_augroup("CodeCompanionHooks", {})

vim.api.nvim_create_autocmd({ "User" }, {
  pattern = "CodeCompanionInline*",
  group = group,
  callback = function(request)
    if request.match == "CodeCompanionInlineFinished" then
      require("conform").format({ bufnr = request.buf })
    end
  end,
})
```

## Event Data

Each event carries a `data` payload. For `CodeCompanionRequestStarted`:

```lua
{
  buf = 10,
  data = {
    adapter = {
      formatted_name = "Copilot",
      model = "o3-mini-2025-01-31",
      name = "copilot"
    },
    bufnr = 10,
    id = 6107753,
    interaction = "chat"
  },
  event = "User",
  file = "CodeCompanionRequestStarted",
  group = 14,
  id = 30,
  match = "CodeCompanionRequestStarted"
}
```

`CodeCompanionRequestFinished` adds a `status`, such as `"success"`, `"error"` or `"cancelled"`.

## Triggering an Event

To make the chat buffer re-check which tools and slash commands are enabled:

```lua
vim.api.nvim_exec_autocmds("User", {
  pattern = "CodeCompanionChatRefreshCache",
})
```

## List of Events

**Chat buffer**

| Event | Fired |
| --- | --- |
| `CodeCompanionChatCreated` | After a chat is created for the first time |
| `CodeCompanionChatOpened` | After a chat is opened |
| `CodeCompanionChatHidden` | After a chat is hidden |
| `CodeCompanionChatClosed` | After a chat is closed for good |
| `CodeCompanionChatSubmitted` | After a message is sent |
| `CodeCompanionChatDone` | After a response is received |
| `CodeCompanionChatStopped` | After a request is stopped |
| `CodeCompanionChatCleared` | After a chat is cleared |
| `CodeCompanionChatRestored` | After a chat is made editable again, such as when `on_before_submit` blocks a message |
| `CodeCompanionChatCompacting` | When a chat starts compacting its messages |
| `CodeCompanionChatAdapter` | After the adapter is set |
| `CodeCompanionChatModel` | After the model is set |
| `CodeCompanionChatToolAdded` | After a tool is added, with the `tool` in the payload |

**Sessions**

| Event | Fired |
| --- | --- |
| `CodeCompanionChatSessionSaved` | After a chat is saved to disk, with its `slug` in the payload |
| `CodeCompanionChatSessionRestored` | After a session is restored, with its `stem` in the payload |
| `CodeCompanionChatSessionsChanged` | After a session is written or deleted |

**ACP**

| Event | Fired |
| --- | --- |
| `CodeCompanionACPConnected` | After the connection is authenticated and ready |
| `CodeCompanionACPSessionPre` | After authentication, before a session starts, so you can change the connection, such as adding MCP servers |
| `CodeCompanionACPSessionPost` | After a session starts |
| `CodeCompanionACPChatRestored` | After a session is restored |
| `CodeCompanionACPCommandsUpdate` | After an agent's commands are loaded, with the `commands` in the payload |
| `CodeCompanionChatACPConfigChanged` | After an agent's configuration options change, with the `config_options` in the payload |

**CLI**

| Event | Fired |
| --- | --- |
| `CodeCompanionCLICreated` | After a CLI buffer is created for the first time |
| `CodeCompanionCLIOpened` | After a CLI buffer is opened |
| `CodeCompanionCLIHidden` | After a CLI buffer is hidden |
| `CodeCompanionCLIClosed` | After a CLI buffer is closed |
| `CodeCompanionCLISent` | After text is sent to a CLI buffer |
| `CodeCompanionCLISubmitted` | When the agent accepts a prompt, however it was typed |
| `CodeCompanionCLIDone` | When the agent finishes a turn |
| `CodeCompanionCLIApprovalRequested` | When the agent is waiting on you, with a `message` in the payload |
| `CodeCompanionCLIApprovalFinished` | When the agent resumes after waiting |

The last four need [agent hooks](/configuration/cli#hooks).

**Requests**

| Event | Fired |
| --- | --- |
| `CodeCompanionRequestStarted` | At the start of a request, or a CLI agent's turn when [hooks](/configuration/cli#hooks) are set up |
| `CodeCompanionRequestStreaming` | At the start of a streaming request |
| `CodeCompanionRequestFinished` | At the end of a request, or a CLI agent's turn when [hooks](/configuration/cli#hooks) are set up |
| `CodeCompanionInlineStarted` | At the start of an inline request |
| `CodeCompanionInlineFinished` | At the end of an inline request |

**Tools**

| Event | Fired |
| --- | --- |
| `CodeCompanionToolsStarted` | When a batch of tools starts |
| `CodeCompanionToolsFinished` | When a batch of tools finishes, is stopped or is cancelled |
| `CodeCompanionToolStarted` | When a tool starts |
| `CodeCompanionToolFinished` | When a tool finishes |
| `CodeCompanionToolApprovalRequested` | When a tool asks for approval |
| `CodeCompanionToolApprovalFinished` | When you approve or reject a tool |
| `CodeCompanionToolQuestionAsked` | When a tool asks you a question |
| `CodeCompanionToolQuestionAnswered` | When you answer or skip a question |
| `CodeCompanionToolsJudgeStarted` | When the [judge](/guides/background-model#tool-judge) starts vetting a tool call |
| `CodeCompanionToolsJudgeFinished` | When the judge returns its verdict |

**Files and diffs**

| Event | Fired |
| --- | --- |
| `CodeCompanionFileEdited` | After a file is edited or created, with the `path` and the `tool` that changed it in the payload |
| `CodeCompanionDiffHunkChanged` | After moving to the next or previous hunk in a diff |

**MCP**

| Event | Fired |
| --- | --- |
| `CodeCompanionMCPServerStart` | When a server starts |
| `CodeCompanionMCPServerReady` | When a server is ready for requests |
| `CodeCompanionMCPServerToolsLoaded` | When a server's tools are loaded |
| `CodeCompanionMCPServerClosed` | When a server closes |
