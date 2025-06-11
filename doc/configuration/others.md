# Other Configuration Options

## Log Level

> [!IMPORTANT]
> By default, logs are stored at `~/.local/state/nvim/codecompanion.log`

When it comes to debugging, you can change the level of logging which takes place in the plugin as follows:

```lua
require("codecompanion").setup({
  opts = {
    log_level = "ERROR", -- TRACE|DEBUG|ERROR|INFO
  },
}),
```

## Default Language

If you use the default system prompt, you can specify which language an LLM should respond in by changing the `opts.language` option:

```lua
require("codecompanion").setup({
  opts = {
    language = "English",
  },
}),
```

Of course, if you have your own system prompt you can specify your own language for the LLM to respond in.

## Sending Code

> [!IMPORTANT]
> Whilst the plugin makes every attempt to prevent code from being sent to the LLM, use this option at your own risk

You can prevent any code from being sent to the LLM with:

```lua
require("codecompanion").setup({
  opts = {
    send_code = false,
  },
}),
```
## Highlight Groups

The plugin sets the following highlight groups during setup:

- `CodeCompanionChatInfo` - Information messages in the chat buffer
- `CodeCompanionChatError` - Error messages in the chat buffer
- `CodeCompanionChatWarn` - Warning messages in the chat buffer
- `CodeCompanionChatSubtext` - Messages that appear under the information, error or warning messages in the chat buffer
- `CodeCompanionChatHeader` - The headers in the chat buffer
- `CodeCompanionChatSeparator` - Separator between headings in the chat buffer
- `CodeCompanionChatTokens` - Virtual text in the chat buffer showing the token count
- `CodeCompanionChatTool` - Tools in the chat buffer
- `CodeCompanionChatToolGroups` - Tool groups in the chat buffer
- `CodeCompanionChatVariable` - Variables in the chat buffer
- `CodeCompanionVirtualText` - All other virtual text in the plugin

