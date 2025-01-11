# Configuring Adapters

An adapter is what connects Neovim to an LLM. It's the interface that allows data to be sent, received and processed and there are a multitude of ways to customize them.

## Changing the Default Adapter

Use the `adapter` field in each strategy:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      adapter = "anthropic",
    },
    inline = {
      adapter = "copilot",
    },
  },
})
```

## Extending an Adapter

Extend a base adapter to set options like `api_key` or `model`:

```lua
require("codecompanion").setup({
  adapters = {
    anthropic = function()
      return require("codecompanion.adapters").extend("anthropic", {
        env = {
          api_key = "MY_OTHER_ANTHROPIC_KEY",
        },
      })
    end,
  },
})
```

If you do not want to store secrets in plain text, prefix commands with `cmd:`:

```lua
require("codecompanion").setup({
  adapters = {
    openai = function()
      return require("codecompanion.adapters").extend("openai", {
        env = {
          api_key = "cmd:op read op://personal/OpenAI/credential --no-newline",
        },
      })
    end,
  },
})
```

## Setting a Proxy

A proxy can be configured by utilising the `adapters.opts` table in the config:

```lua
require("codecompanion").setup({
  adapters = {
    opts = {
      allow_insecure = true,
      proxy = "socks5://127.0.0.1:9999",
    },
  },
})
```

## Changing a Model

Many adapters allow model selection via the `schema.model.default` property:

```lua
require("codecompanion").setup({
  adapters = {
    openai = function()
      return require("codecompanion.adapters").extend("openai", {
        schema = {
          model = {
            default = "gpt-4",
          },
        },
      })
    end,
  },
})
```
## Example: Azure OpenAI

Below is an example of how you can leverage the `azure_openai` adapter within the plugin:

```lua
require("codecompanion").setup({
  adapters = {
    azure_openai = function()
      return require("codecompanion.adapters").extend("azure_openai", {
        env = {
          api_key = "YOUR_AZURE_OPENAI_API_KEY",
          endpoint = "YOUR_AZURE_OPENAI_ENDPOINT",
        },
        schema = {
          model = {
            default = "YOUR_DEPLOYMENT_NAME",
          },
        },
      })
    end,
  },
  strategies = {
    chat = {
      adapter = "azure_openai",
    },
    inline = {
      adapter = "azure_openai",
    },
  },
})
```

