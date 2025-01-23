# Configuring Adapters

> [!NOTE]
  > The adapters that the plugin supports out of the box can be found [here](https://github.com/olimorris/codecompanion.nvim/tree/main/lua/codecompanion/adapters). It is recommended that you review them so you better understand the settings that can be customized

An adapter is what connects Neovim to an LLM. It's the interface that allows data to be sent, received and processed and there are a multitude of ways to customize them.

## Changing the Default Adapter

You can change the default adapter as follows:

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
}),
```

## Setting an API Key

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
}),
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
}),
```

> [!NOTE]
> In this example, we're using the 1Password CLI to extract the OpenAI API Key. You could also use gpg as outlined [here](https://github.com/olimorris/codecompanion.nvim/discussions/601)

## Configuring Adapter Settings

LLMs have many settings such as model, temperature and max_tokens. In an adapter, these sit within a schema table and can be configured during setup:

```lua
require("codecompanion").setup({
  adapters = {
    llama3 = function()
      return require("codecompanion.adapters").extend("ollama", {
        name = "llama3", -- Give this adapter a different name to differentiate it from the default ollama adapter
        schema = {
          model = {
            default = "llama3:latest",
          },
          num_ctx = {
            default = 16384,
          },
          num_predict = {
            default = -1,
          },
        },
      })
    end,
  },
})
```

## Adding a Custom Adapter

> [!NOTE]
> See the [Creating Adapters](/extending/adapters) section to learn how to create custom adapters

Custom adapters can be added to the plugin as follows:

```lua
require("codecompanion").setup({
  adapters = {
    my_custom_adapter = function()
      return {} -- My adapter logic
    end,
  },
}),
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
}),
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
}),
```

## Example: Using OpenAI Compatible Models

To use any other OpenAI compatible models, change the URL in the env table, set an API key:

```lua
require("codecompanion").setup({
  adapters = {
    ollama = function()
      return require("codecompanion.adapters").extend("openai_compatible", {
        env = {
          url = "http[s]://open_compatible_ai_url", -- optional: default value is ollama url http://127.0.0.1:11434
          api_key = "OpenAI_API_KEY", -- optional: if your endpoint is authenticated
          chat_url = "/v1/chat/completions", -- optional: default value, override if different
        },
      })
    end,
  },
})
```

## Example: Using Ollama Remotely

To use Ollama remotely, change the URL in the env table, set an API key and pass it via an "Authorization" header:

```lua
require("codecompanion").setup({
  adapters = {
    ollama = function()
      return require("codecompanion.adapters").extend("ollama", {
        env = {
          url = "https://my_ollama_url",
          api_key = "OLLAMA_API_KEY",
        },
        headers = {
          ["Content-Type"] = "application/json",
          ["Authorization"] = "Bearer ${api_key}",
        },
        parameters = {
          sync = true,
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
}),
```

## Example: Using DeepSeek R1

```lua
require("codecompanion").setup({
  adapters = {
    deepseek = function()
      return require("codecompanion.adapters").extend("deepseek", {
        env = {
          api_key = "DeepSeek_API_KEY", -- See note above about using cmd for secure API key storage
        },
        schema = {
          model = {
            default = "deepseek-reasoner",
          },
        },
      })
    end,
  },
  strategies = {
    chat = {
      adapter = "deepseek",
    },
    inline = {
      adapter = "deepseek",
    },
  },

}),

```
