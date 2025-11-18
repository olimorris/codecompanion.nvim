---
description: Learn how to configure ACP adapters like Claude Code, Gemini CLI and Codex
---

# Configuring Agent Client Protocol (ACP)

This section contains configuration which is specific to ACP adapters only. There is a lot of shared functionality between ACP and [http](/configuration/adapters) adapters. Therefore it's recommended you read the two pages together.

## Setup: Auggie CLI from Augment Code

To use [Auggie CLI](https://docs.augmentcode.com/cli/overview) within CodeCompanion, you simply need to follow their [Getting Started](https://docs.augmentcode.com/cli/overview#getting-started) guide.

## Setup: Cagent

To use Docker's [Cagent](https://github.com/docker/cagent) within CodeCompanion, you need to follow these steps:

1. [Install](https://github.com/docker/cagent?tab=readme-ov-file#installation) Cagent as per their instructions
2. [Create an agent](https://github.com/docker/cagent?tab=readme-ov-file#run-agents) in the repository you're working from
3. Test the agent by running `cagent run your_agent.yaml` in the CLI
4. In your CodeCompanion config, extend the `cagent` adapter to include the agent:

```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      cagent = function()
        return require("codecompanion.adapters").extend("cagent", {
          commands = {
            default = {
              "cagent",
              "acp",
              "your_agent.yaml",
            },
          },
        })
      end,
    },
  },
})
```

If you have multiple agent files that you like to run separately, you can create multiple commands for each agent.

## Setup: Claude Code

To use [Claude Code](https://www.anthropic.com/claude-code) within CodeCompanion, you'll need to take the following steps:

1. [Install](https://docs.anthropic.com/en/docs/claude-code/quickstart#step-1%3A-install-claude-code) Claude Code
2. [Install](https://github.com/zed-industries/claude-code-acp) the Zed ACP adapter for Claude Code

### Using Claude Pro Subscription

3. In your CLI, run `claude setup-token`. You'll be redirected to the Claude.ai website for authorization:
<img src="https://github.com/user-attachments/assets/28b70ba1-6fd2-4431-9905-c60c83286e4c">
4. Back in your CLI, copy the OAuth token (in yellow):
<img src="https://github.com/user-attachments/assets/73992480-20a6-4858-a9fe-93a4e49004ff">
5. In your CodeCompanion config, extend the `claude_code` adapter and include the OAuth token (see the section on [environment variables and setting API keys](/configuration/adapters#environment-variables-setting-an-api-key) for other ways to do this):
```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      claude_code = function()
        return require("codecompanion.adapters").extend("claude_code", {
          env = {
            CLAUDE_CODE_OAUTH_TOKEN = "my-oauth-token",
          },
        })
      end,
    },
  },
})
```

### Using an API Key

3. [Create](https://console.anthropic.com/settings/keys) an API key in your Anthropic console.
4. In your CodeCompanion config, extend the `claude_code` adapter and set the `ANTHROPIC_API_KEY`:
```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      claude_code = function()
        return require("codecompanion.adapters").extend("claude_code", {
          env = {
            ANTHROPIC_API_KEY = "my-api-key",
          },
        })
      end,
    },
  },
})
```

## Setup: Codex

To use OpenAI's [Codex](https://openai.com/codex/), install an ACP-compatible adapter like [this](https://github.com/zed-industries/codex-acp) one from [Zed](https://zed.dev).

By default, the adapter will look for an `OPENAI_API_KEY` in your shell, however you can also authenticate via ChatGPT. This can be customized in the plugin configuration:

```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      codex = function()
        return require("codecompanion.adapters").extend("codex", {
          defaults = {
            auth_method = "openai-api-key", -- "openai-api-key"|"codex-api-key"|"chatgpt"
          },
          env = {
            OPENAI_API_KEY = "my-api-key",
          },
        })
      end,
    },
  },
})
```

## Setup: Gemini CLI

1. Install [Gemini CLI](https://github.com/google-gemini/gemini-cli)
2. Update your CodeCompanion config and select which authentication methods you'd like to use. Currently there are:
    - `oauth-personal` which uses your Google login
    - `gemini-api-key`
    - `vertex-ai`)

The example below uses the `gemini-api-key` method, pulling the API key from [1Password CLI](https://developer.1password.com/docs/cli/get-started/):

```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      gemini_cli = function()
        return require("codecompanion.adapters").extend("gemini_cli", {
          defaults = {
            auth_method = "gemini-api-key", -- "oauth-personal"|"gemini-api-key"|"vertex-ai"
          },
          env = {
            GEMINI_API_KEY = "cmd:op read op://personal/Gemini_API/credential --no-newline",
          },
        })
      end,
    },
  },
})
```

## Setup: Goose CLI

To use [Goose](https://block.github.io/goose/) in CodeCompanion, ensure you've followed their [documentation](https://block.github.io/goose/docs/getting-started/installation/) to setup and install Goose CLI. Then ensure that in your chat buffer you select the `goose` adapter.

## Setup: Kimi CLI

Install [Kimi CLI](https://github.com/MoonshotAI/kimi-cli?tab=readme-ov-file#installation) as per their instructions. Then in the CLI, run `kimi` followed by `/setup` to configure your API key. Then ensure that in your chat buffer you select the `kimi_cli` adapter.

## Setup: opencode

To use [opencode](https://opencode.ai) in CodeCompanion, ensure you've followed their documentation to [install](https://opencode.ai/docs/#install) and [configure](https://opencode.ai/docs/#configure) it. Then ensure that in your chat buffer you select the `opencode` adapter.

