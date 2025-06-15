# Events / Hooks

In order to enable a tighter integration between CodeCompanion and your Neovim config, the plugin fires events at various points during its lifecycle.

## List of Events

The events that are fired from within the plugin are:

- `CodeCompanionChatCreated` - Fired after a chat has been created for the first time
- `CodeCompanionChatOpened` - Fired after a chat has been opened
- `CodeCompanionChatHidden` - Fired after a chat has been hidden
- `CodeCompanionChatClosed` - Fired after a chat has been permanently closed
- `CodeCompanionChatSubmitted` - Fired after a chat has been submitted
- `CodeCompanionChatStopped` - Fired after a chat has been stopped
- `CodeCompanionChatCleared` - Fired after a chat has been cleared
- `CodeCompanionChatAdapter` - Fired after the adapter has been set in the chat
- `CodeCompanionChatModel` - Fired after the model has been set in the chat
- `CodeCompanionChatPin` - Fired after a pinned reference has been updated in the messages table
- `CodeCompanionAgentStarted` - Fired when an agent has been initiated to run tools
- `CodeCompanionAgentFinished` - Fired when an agent has finished running all tools
- `CodeCompanionToolAdded` - Fired when a tool has been added to a chat
- `CodeCompanionToolStarted` - Fired when a tool has started executing
- `CodeCompanionToolFinished` - Fired when a tool has finished executing
- `CodeCompanionInlineStarted` - Fired at the start of the Inline strategy
- `CodeCompanionInlineFinished` - Fired at the end of the Inline strategy
- `CodeCompanionRequestStarted` - Fired at the start of any API request
- `CodeCompanionRequestStreaming` - Fired at the start of a streaming API request
- `CodeCompanionRequestFinished` - Fired at the end of any API request
- `CodeCompanionDiffAttached` - Fired when in Diff mode
- `CodeCompanionDiffDetached` - Fired when exiting Diff mode
- `CodeCompanionDiffAccepted` - Fired when a user accepts a change
- `CodeCompanionDiffRejected` - Fired when a user rejects a change

There are also events that can be utilized to trigger commands from within the plugin:

- `CodeCompanionChatRefreshCache` - Used to refresh conditional elements in the chat buffer

## Event Data

Each event also comes with a data payload. For example, with `CodeCompanionRequestStarted`:

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
    strategy = "chat"
  },
  event = "User",
  file = "CodeCompanionRequestStarted",
  group = 14,
  id = 30,
  match = "CodeCompanionRequestStarted"
}
```

And the `CodeCompanionRequestFinished` also has a `data.status` value.

## Consuming an Event

Events can be hooked into as follows:

```lua
local group = vim.api.nvim_create_augroup("CodeCompanionHooks", {})

vim.api.nvim_create_autocmd({ "User" }, {
  pattern = "CodeCompanionInline*",
  group = group,
  callback = function(request)
    if request.match == "CodeCompanionInlineFinished" then
      -- Format the buffer after the inline request has completed
      require("conform").format({ bufnr = request.buf })
    end
  end,
})
```

You can trigger an event with:

```lua
vim.api.nvim_exec_autocmds("User", {
  pattern = "CodeCompanionChatRefreshCache",
})
```

