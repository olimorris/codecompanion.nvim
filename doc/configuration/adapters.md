---
description: Learn how to configure adapters like OpenAI, Anthropic, Claude Code in CodeCompanion
---

# Configuring Adapters

> [!TIP]
> Want to connect to an LLM that isn't supported out of the box? Check out
> [these](#community-adapters) user contributed adapters, [create](/extending/adapters.html) your own or post in the [discussions](https://github.com/olimorris/codecompanion.nvim/discussions)

An adapter is what connects Neovim to an LLM provider and model. It's the interface that allows data to be sent, received and processed. There are a multitude of ways to customize them.

There are two "types" of adapter in CodeCompanion; **http** adapters which connect you to an LLM and [ACP](/configuration/acp) adapters which leverage the [Agent Client Protocol](https://agentclientprotocol.com) to connect you to an agent.

The configuration for both types of adapters is exactly the same, however they sit within their own tables (`adapters.http.*` and `adapters.acp.*`) and have different options available. HTTP adapters use _models_ to allow users to select the specific LLM they'd like to interact with. ACP adapters use _commands_ to allow users to customize their interaction with agents (e.g. enabling _yolo_ mode). As there is a lot of shared functionality between the two adapters, it is recommend that you read this page alongside the ACP one.

## Changing the Default Adapter

You can change the default adapter for each strategy as follows:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      adapter = "anthropic",
    },
    inline = {
      adapter = "copilot",
    },
    cmd = {
      adapter = "deepseek",
    }
  },
}),
```

## Setting an API Key

Extend a base adapter to set options like `api_key` or `model`:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      anthropic = function()
        return require("codecompanion.adapters").extend("anthropic", {
          env = {
            api_key = "MY_OTHER_ANTHROPIC_KEY",
          },
        })
      end,
    },
  },
})
```

If you do not want to store secrets in plain text, prefix commands with `cmd:`:

```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      gemini_cli = function()
        return require("codecompanion.adapters").extend("gemini_cli", {
          env = {
            api_key = "cmd:op read op://personal/Gemini/credential --no-newline",
          },
        })
      end,
    },
  },
})
```

> [!NOTE]
> In this example, we're using the 1Password CLI to extract the Gemini API Key. You could also use gpg as outlined [here](https://github.com/olimorris/codecompanion.nvim/discussions/601)

## Environment Variables

Setting environment variables within adapters is a key part of configuration. The adapter `env` table lets you define values that will be interpolated into the adapter's URL, headers, parameters and other fields at runtime.

Supported `env` value types:
- **Plain environment variable name (string)**: if the value is the name of an environment variable that has already been set (e.g. `"HOME"` or `"GEMINI_API_KEY"`), the plugin will read the value.
- **Command (string prefixed with `cmd:`)**: any value that starts with `cmd:` will be executed via the shell. Example: `"cmd:op read op://personal/Gemini/credential --no-newline"`.
- **Function**: you can provide a Lua function which returns a string and will be called with the adapter as its sole argument.
- **Schema reference (dot notation)**: you can reference values from the adapter table (for example `"schema.model.default"`).

## Changing a Model

To more easily change a model for a HTTP adapter, you can pass in the `name` and `model` to the adapter:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      adapter = {
        name = "copilot",
        model = "claude-sonnet-4",
      },
    },
  },
}),

```

To change the default model on an adapter you can modify the `schema.model.default` property:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      openai = function()
        return require("codecompanion.adapters").extend("openai", {
          schema = {
            model = {
              default = "gpt-4.1",
            },
          },
        })
      end,
    },
  },
}),
```

## Configuring Adapter Settings

> [!NOTE]
> When extending an adapter with `.extend`, use it's key from the `adapters` dictionary

LLMs have many settings such as model, temperature and max_tokens. In an adapter, these sit within a schema table and can be configured during setup:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      qwen3 = function()
        return require("codecompanion.adapters").extend("ollama", {
          name = "qwen3", -- Give this adapter a different name to differentiate it from the default ollama adapter
          opts = {
            vision = true,
            stream = true,
          },
          schema = {
            model = {
              default = "qwen3:latest",
            },
            num_ctx = {
              default = 16384,
            },
            think = {
              default = false,
            },
            keep_alive = {
              default = "5m",
            },
          },
        })
      end,
    },
  },
})
```

Or, in the case of an ACP adapter:

```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      gemini_cli = function()
        return require("codecompanion.adapters").extend("gemini_cli", {
          commands = {
            default = {
              "node",
              "/Users/Oli/Code/try/gemini-cli/packages/cli",
              "--experimental-acp",
            },
          },
          defaults = {
            auth_method = "gemini-api-key",
            mcpServers = {},
            timeout = 20000, -- 20 seconds
          },
          env = {
            GEMINI_API_KEY = "GEMINI_API_KEY",
          },
        })
      end,
    },
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
    http = {
      my_custom_adapter = function()
        return {} -- My adapter logic
      end,
    },
  },
})
```

## Setting a Proxy

A proxy can be configured by utilising the `adapters.opts` table in the config:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      opts = {
        allow_insecure = true,
        proxy = "socks5://127.0.0.1:9999",
      },
    },
  },
}),
```

## Community Adapters

Thanks to the community for building the following adapters:

- [Venice.ai](https://github.com/olimorris/codecompanion.nvim/discussions/972)
- [Fireworks.ai](https://github.com/olimorris/codecompanion.nvim/discussions/693)
- [OpenRouter](https://github.com/olimorris/codecompanion.nvim/discussions/1013)
- [DashScope](https://github.com/olimorris/codecompanion.nvim/discussions/2239)

The section of the discussion forums which is dedicated to user created adapters can be found [here](https://github.com/olimorris/codecompanion.nvim/discussions?discussions_q=is%3Aopen+label%3A%22tip%3A+adapter%22). Use these individual threads as a place to raise issues and ask questions about your specific adapters.

## Hiding Default Adapters

By default, the plugin shows all available adapters, including the defaults. If you prefer to only display the adapters defined in your user configuration, you can set the `show_defaults` option to `false`:

```lua
require("codecompanion").setup({
  adapters = {
    acp = {
      opts = {
        show_defaults = false,
      },
      -- Define your custom adapters here
    },
    http = {
      opts = {
        show_defaults = false,
      },
      -- Define your custom adapters here
    },
  },
})
```

## Controlling Model Choices

When switching between adapters, the plugin typically displays all available model choices for the selected adapter. If you want to simplify the interface and have the default model automatically chosen (without showing any model selection UI), you can set the `show_model_choices` option to `false`:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      -- Define your custom adapters here
      opts = {
        show_model_choices = false,
      },
    },
  },
})
```

With `show_model_choices = false`, the default model (as defined in the adapter's schema) will be automatically selected when changing adapters, and no model selection will be shown to the user.

## Setup: OpenAI Responses API

CodeCompanion supports OpenAI's [Responses API](https://platform.openai.com/docs/api-reference/responses) out of the box, via a separate adapter:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      adapter = "openai_responses",
    },
    inline = {
      adapter = "openai_responses",
    },
  },
}),
```

and it can be configured as with any other adapter:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      openai_responses = function()
        return require("codecompanion.adapters").extend("openai_responses", {
          env = {
            api_key = "OPENAI_API_KEY",
          },
        })
      end,
    },
  },
},
```

By default, CodeCompanion sets `store = false` to ensure that state isn't [stored](https://platform.openai.com/docs/api-reference/responses/create#responses-create-store) via the API. This is standard behaviour across all http adapters within the plugin.

## Setup: Using Ollama Remotely

To use Ollama remotely, change the URL in the env table, set an API key and pass it via an "Authorization" header:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
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
  },
})
```

## Setup: Azure OpenAI

Below is an example of how you can leverage the `azure_openai` adapter within the plugin:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
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

## Setup: OpenRouter with Reasoning Output

```lua 
require("codecompanion").setup({
  adapters = {
    http = {
      openrouter = function()
        return require("codecompanion.adapters").extend("openai_compatible", {
          env = {
            url = "https://openrouter.ai/api",
            api_key = "OPENROUTER_API_KEY",
            chat_url = "/v1/chat/completions",
          },
          handlers = {
            parse_extra = function(self, data)
              local extra = data.extra
              if extra and extra.reasoning then
                data.output.reasoning = { content = extra.reasoning }
                if data.output.content == "" then
                  data.output.content = nil
                end
              end
              return data
            end,
          },
        })
      end,
    },
  },
  strategies = {
    chat = {
      adapter = "openrouter",
    },
    inline = {
      adapter = "openrouter",
    },
  },
})
```
