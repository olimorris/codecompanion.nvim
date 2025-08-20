# CodeCompanion - Agent Client Protocol

Implementation of ACP within CodeCompanion.

## How to get started

1. Ensure you have [gemini-cli](https://github.com/google-gemini/gemini-cli) installed
2. Clone this repo locally
3. Install the plugin using Lazy.nvim:

```lua
{
    dir = "/Users/Oli/Code/Neovim/agent-client-protocol",
    name = "codecompanion",
    opts = {
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
        opts = {
            log_level = "DEBUG",
        },
    },
},
```

4. From here on in, most of the [docs](https://codecompanion.olimorris.dev) should apply

## In Action

https://github.com/user-attachments/assets/7f15d877-eb27-45a8-bc79-c6ff859937ce
