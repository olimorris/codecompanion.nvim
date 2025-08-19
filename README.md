# CodeCompanion - Agent Client Protocol

Implementation of ACP within CodeCompanion.

## How to get started

1. Ensure you have [gemini-cli](https://github.com/google-gemini/gemini-cli) installed
2. [Install](https://codecompanion.olimorris.dev/installation.html) CodeCompanion
3. Setup with:

```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      gemini_cli = function()
        return require("codecompanion.adapters").extend("gemini_cli", {
          env = {
            -- and point Gemini to your API key. This could be:
            -- 1. A name of an environment variable
            -- 2. A cmd to your password vault
            GEMINI_API_KEY = "cmd:op read op://personal/Gemini_API/credential --no-newline",
          },
        })
      end,
    },
  },
  strategies = {
    chat = {
      adapter = "gemini_cli",
    },
  },
})
```

## In Action

https://github.com/user-attachments/assets/7f15d877-eb27-45a8-bc79-c6ff859937ce
