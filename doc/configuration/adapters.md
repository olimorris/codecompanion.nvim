# Configuring Adapters

> [!TIP]
> Want to connect to an LLM that isn't supported out of the box? Check out
> [these](#community-adapters) user contributed adapters, [create](/extending/adapters.html) your own or post in the [discussions](https://github.com/olimorris/codecompanion.nvim/discussions)

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

Environment variables can also be functions and as a parameter, they receive a copy of the adapter itself.

## Changing a Model

To more easily change a model associated with a strategy you can pass in the `name` and `model` to the adapter:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      adapter = {
        name = "copilot",
        model = "claude-sonnet-4-20250514",
      },
    },
  },
}),

```

To change the default model on an adapter you can modify the `schema.model.default` property:

```lua
require("codecompanion").setup({
  adapters = {
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
}),
```

## Configuring Adapter Settings

LLMs have many settings such as model, temperature and max_tokens. In an adapter, these sit within a schema table and can be configured during setup:

```lua
require("codecompanion").setup({
  adapters = {
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
            -- or, if you want to automatically turn on `think` for certain models:
            default = function(adapter)
              -- this'll set `think` to true if the model name contain `qwen3` or `deepseek-r1`
              local model_name = adapter.model.name:lower()
              return vim.iter({ "qwen3", "deepseek-r1" }):any(function(kw)
                return string.find(model_name, kw) ~= nil
              end)
            end,
          },
          keep_alive = {
            default = '5m',
          }
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

## Community Adapters

Thanks to the community for building the following adapters:

- [Venice.ai](https://github.com/olimorris/codecompanion.nvim/discussions/972)
- [Fireworks.ai](https://github.com/olimorris/codecompanion.nvim/discussions/693)
- [OpenRouter](https://github.com/olimorris/codecompanion.nvim/discussions/1013)

The section of the discussion forums which is dedicated to user created adapters can be found [here](https://github.com/olimorris/codecompanion.nvim/discussions?discussions_q=is%3Aopen+label%3A%22tip%3A+adapter%22). Use these individual threads as a place to raise issues and ask questions about your specific adapters.

## Example: Using OpenAI Compatible Models

If your LLM states that it is _"OpenAI compatible"_, then you can leverage the `openai_compatible` adapter, modifying some elements such as the URL in the env table, the API key and altering the schema:

> [!NOTE]
> The schema in this instance is provided only as an example and must be modified according to the requirements of the model you use. The options are chosen to show how to use different types of parameters.

```lua
require("codecompanion").setup({
  adapters = {
    my_openai = function()
      return require("codecompanion.adapters").extend("openai_compatible", {
        env = {
          url = "http[s]://open_compatible_ai_url", -- optional: default value is ollama url http://127.0.0.1:11434
          api_key = "OpenAI_API_KEY", -- optional: if your endpoint is authenticated
          chat_url = "/v1/chat/completions", -- optional: default value, override if different
          models_endpoint = "/v1/models", -- optional: attaches to the end of the URL to form the endpoint to retrieve models
        },
        schema = {
          model = {
            default = "deepseek-r1-671b",  -- define llm model to be used
          },
          temperature = {
            order = 2,
            mapping = "parameters",
            type = "number",
            optional = true,
            default = 0.8,
            desc = "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
            validate = function(n)
              return n >= 0 and n <= 2, "Must be between 0 and 2"
            end,
          },
          max_completion_tokens = {
            order = 3,
            mapping = "parameters",
            type = "integer",
            optional = true,
            default = nil,
            desc = "An upper bound for the number of tokens that can be generated for a completion.",
            validate = function(n)
              return n > 0, "Must be greater than 0"
            end,
          },
          stop = {
            order = 4,
            mapping = "parameters",
            type = "string",
            optional = true,
            default = nil,
            desc = "Sets the stop sequences to use. When this pattern is encountered the LLM will stop generating text and return. Multiple stop patterns may be set by specifying multiple separate stop parameters in a modelfile.",
            validate = function(s)
              return s:len() > 0, "Cannot be an empty string"
            end,
          },
          logit_bias = {
            order = 5,
            mapping = "parameters",
            type = "map",
            optional = true,
            default = nil,
            desc = "Modify the likelihood of specified tokens appearing in the completion. Maps tokens (specified by their token ID) to an associated bias value from -100 to 100. Use https://platform.openai.com/tokenizer to find token IDs.",
            subtype_key = {
              type = "integer",
            },
            subtype = {
              type = "integer",
              validate = function(n)
                return n >= -100 and n <= 100, "Must be between -100 and 100"
              end,
            },
          },
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

## Hiding Default Adapters

By default, the plugin shows all available adapters, including the defaults. If you prefer to only display the adapters defined in your user configuration, you can set the `show_defaults` option to `false`:

```lua
require("codecompanion").setup({
  adapters = {
    opts = {
      show_defaults = false,
    },
    -- Define your custom adapters here
  },
})
```

## Controlling Model Choices

When switching between adapters, the plugin typically displays all available model choices for the selected adapter. If you want to simplify the interface and have the default model automatically chosen (without showing any model selection UI), you can set the `show_model_choices` option to `false`:

```lua
require("codecompanion").setup({
  adapters = {
    opts = {
      show_model_choices = false,
    },
    -- Define your custom adapters here
  },
})
```

With `show_model_choices = false`, the default model (as defined in the adapter's schema) will be automatically selected when changing adapters, and no model selection will be shown to the user.
