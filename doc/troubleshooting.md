---
description: "Diagnose problems with CodeCompanion in Neovim with the health check, the log file and the debug window."
---

# Troubleshooting

When something doesn't work, start with the health check, then the log file. To see exactly what's sent to the LLM, use the debug window.

## Health Check

To check CodeCompanion's dependencies, Tree-sitter parsers and libraries:

```
:checkhealth codecompanion
```

It also prints the path to the log file.

## Log File

Errors are written to `codecompanion.log` in Neovim's log directory, `stdpath("log")`. For more detail, raise the log level:

```lua
require("codecompanion").setup({
  opts = {
    log_level = "DEBUG", -- Can be "TRACE", "DEBUG", "INFO" or "ERROR"
  },
})
```

At `DEBUG`, every request is logged, along with the paths of the files holding its body and response. Set the level back to `ERROR` once you're done, as the log grows quickly.

## Debug Window

Press `gd` in a chat buffer to open the [debug window](/usage/chat-buffer/#debug-window). It shows the adapter's settings and the full message history that's sent on the next turn, including the system prompt and anything hidden from the chat buffer.

## Minimal Config

To rule out your own config and other plugins, reproduce the problem with [minimal.lua](https://github.com/olimorris/codecompanion.nvim/blob/main/minimal.lua):

```sh
nvim --clean -u minimal.lua
```

Include your `minimal.lua` and the relevant lines from the log when you [open an issue](https://github.com/olimorris/codecompanion.nvim/issues).
