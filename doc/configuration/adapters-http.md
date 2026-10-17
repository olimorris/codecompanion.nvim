---
description: "Connect CodeCompanion to an LLM provider, and set its API key, model and parameters."
---

# Configuring HTTP Adapters

An _adapter_ connects CodeCompanion to an LLM provider or an agent. HTTP adapters, set under `adapters.http`, call an LLM's API directly, with CodeCompanion supplying the system prompt, tools and agent loop. [ACP adapters](/configuration/adapters-acp), set under `adapters.acp`, connect to an agent that brings its own. Both are configured in the same way, so read the two pages together.

> [!TIP]
> For a provider that isn't built in, try a [community adapter](#community-adapters) or [create your own](/extending/adapters)

## Built-in Adapters

| Adapter | API key | Default model |
| --- | --- | --- |
| `anthropic` | `ANTHROPIC_API_KEY` | `claude-sonnet-5` |
| `azure_openai` | `AZURE_OPENAI_API_KEY` and `AZURE_OPENAI_ENDPOINT` | None, set your deployment name |
| `copilot` | Your Copilot sign-in | `auto` |
| `deepseek` | `DEEPSEEK_API_KEY` | `deepseek-v4-flash` |
| `gemini` | `GEMINI_API_KEY` | `gemini-3.1-pro-preview` |
| `gemini_legacy` | `GEMINI_API_KEY` | `gemini-3.1-pro-preview` |
| `huggingface` | `HUGGINGFACE_API_KEY` | `Qwen/Qwen2.5-32B-Instruct` |
| `kimi` | `MOONSHOT_API_KEY` | `kimi-k2.7-code` |
| `mistral` | `MISTRAL_API_KEY` | `mistral-small-latest` |
| `novita` | `NOVITA_API_KEY` | `meta-llama/llama-3.1-8b-instruct` |
| `ollama` | None, set `OLLAMA_HOST` for a remote server | A model from your Ollama server |
| `openai` | `OPENAI_API_KEY` | `gpt-5.6-luna` |
| `openai_legacy` | `OPENAI_API_KEY` | `gpt-4.1` |
| `openrouter` | `OPENROUTER_API_KEY` | `openai/gpt-5.4-mini` |
| `xai` | `XAI_API_KEY` | `grok-beta` |

`gemini` uses Google's Interactions API and `gemini_legacy` uses `generateContent`. `openai` uses the Responses API and `openai_legacy` uses Chat Completions. For llama.cpp, LM Studio and other servers that speak the OpenAI API, extend `openai_compatible`, as covered in [Connecting an OpenAI-Compatible Provider](/guides/openai-compatible-providers).

The `duckduckgo`, `jina`, `markitdown`, `serply` and `tavily` adapters power the [web search](/guides/web-search) and fetch tools rather than chat.

## Changing the Default Adapter

To set the adapter for each interaction:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      adapter = "anthropic",
    },
    inline = {
      adapter = "copilot",
    },
    cmd = {
      adapter = "deepseek",
    },
  },
})
```

## Changing the Default Model

Set the model on the interaction, or on the adapter so it applies everywhere:

::: code-group

```lua [For Interactions] {4-7}
require("codecompanion").setup({
  interactions = {
    chat = {
      adapter = {
        name = "openai",
        model = "gpt-4.1",
      },
    },
  },
})
```

```lua [For Adapters] {6-10}
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
})
```

:::

## Customising an Adapter

There are two ways to customise a built-in adapter, and this page uses both:

- **Function** - For full or computed setups, such as a custom `url`, `headers` or `schema`, or values resolved when the adapter loads
- **`extend` table** - For static overrides, such as credentials or a default value

::: code-group

```lua [Function]
require("codecompanion").setup({
  adapters = {
    http = {
      anthropic = function()
        return require("codecompanion.adapters").extend("anthropic", {
          env = { api_key = "cmd:op read op://personal/Anthropic/credential --no-newline" },
        })
      end,
    },
  },
})
```

```lua [Extend Table]
require("codecompanion").setup({
  adapters = {
    http = {
      extend = {
        anthropic = { env = { api_key = "cmd:op read op://personal/Anthropic/credential --no-newline" } },
      },
    },
  },
})
```

:::

> [!IMPORTANT]
> Each key in `extend` is the adapter's key under `adapters.http`, not the adapter's `name`

## Changing Adapter Parameters (Schema)

An adapter's parameters, such as `model`, `temperature` and `max_output_tokens`, sit in its `schema` table. To change a default:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      openai = function()
        return require("codecompanion.adapters").extend("openai", {
          schema = {
            temperature = {
              default = 0.2,
            },
          },
        })
      end,
    },
  },
})
```

A parameter's `enabled` function takes the adapter and decides whether the parameter is sent. To leave `temperature` out for Codex models:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      openai = function()
        return require("codecompanion.adapters").extend("openai", {
          schema = {
            temperature = {
              enabled = function(self)
                local model = require("codecompanion.adapters.utils").model(self)
                return not (model and model:find("codex"))
              end,
            },
          },
        })
      end,
    },
  },
})
```

## Adding a Custom Adapter

Add your own adapter alongside the built-in ones:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      my_custom_adapter = function()
        return {} -- Your adapter
      end,
    },
  },
})
```

See [Creating Adapters](/extending/adapters) for what goes in the table.

## Background Interaction Adapters

[Background interactions](/guides/background-model) send requests to an LLM without any input from you, such as to generate a chat title. They use `interactions.background.adapter`, which you can override for a single action:

```lua
require("codecompanion").setup({
  interactions = {
    background = {
      chat = {
        callbacks = {
          ["on_ready"] = {
            actions = {
              {
                path = "interactions.background.builtin.chat_make_title",
                adapter = { name = "copilot", model = "claude-haiku-4.5" },
              },
            },
          },
        },
      },
    },
  },
})
```

## Controlling Model Choices

Changing adapter with `ga` asks you to pick a model when the adapter has more than one. To use the adapter's default model without asking:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      opts = {
        show_model_choices = false,
      },
    },
  },
})
```

Model lists fetched from a provider are cached for 1800 seconds, set with `adapters.http.opts.cache_models_for`.

## Environment Variables

An adapter's `env` table holds values, such as an API key, that are resolved on every request and substituted into its URL, headers and parameters:

::: code-group

```lua{7} [Environment Variable]
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

```lua{7} [Command]
require("codecompanion").setup({
  adapters = {
    http = {
      anthropic = function()
        return require("codecompanion.adapters").extend("anthropic", {
          env = {
            api_key = "cmd:op read op://personal/Anthropic/credential --no-newline",
          },
        })
      end,
    },
  },
})
```

```lua{7-9} [Function]
require("codecompanion").setup({
  adapters = {
    http = {
      anthropic = function()
        return require("codecompanion.adapters").extend("anthropic", {
          env = {
            api_key = function()
              return my_custom_api_key_fetcher()
            end,
          },
        })
      end,
    },
  },
})
```

```lua{7} [Schema Reference]
require("codecompanion").setup({
  adapters = {
    http = {
      anthropic = function()
        return require("codecompanion.adapters").extend("anthropic", {
          env = {
            model_for_url = "schema.model.default",
          },
        })
      end,
    },
  },
})
```

```lua{7} [File]
require("codecompanion").setup({
  adapters = {
    http = {
      anthropic = function()
        return require("codecompanion.adapters").extend("anthropic", {
          env = {
            api_key = "file:~/.dotfiles/.anthropic_api_key",
          },
        })
      end,
    },
  },
})
```

:::

| Value | Resolves to |
| --- | --- |
| `"cmd:op read ..."` | The output of the shell command, such as the [1Password CLI](https://developer.1password.com/docs/cli/) or [gpg](https://github.com/olimorris/codecompanion.nvim/discussions/601) |
| `"file:~/.anthropic_api_key"` | The file's contents, with a relative path read from the current working directory |
| `"ANTHROPIC_API_KEY"` | The environment variable of that name |
| A function | Its return value, called with the adapter |
| `"schema.model.default"` | The value at that path in the adapter |
| Anything else | The value as written |

Commands time out after 20 seconds. To change this:

```lua
require("codecompanion").setup({
  adapters = {
    opts = {
      cmd_timeout = 30000, -- milliseconds
    },
  },
})
```

## Disabling Compaction

The `anthropic` and `openai` adapters use the provider's server-side compaction to manage context. To turn it off:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      anthropic = function()
        return require("codecompanion.adapters").extend("anthropic", {
          opts = {
            compaction = false,
          },
        })
      end,
    },
  },
})
```

## Hiding Adapters

Adapters in the `hidden` table are left out of the adapter picker. Set one to `false` to show it again:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      opts = {
        hidden = { my_custom_adapter = true, tavily = false },
      },
    },
  },
})
```

By default, `duckduckgo`, `jina`, `markitdown` and `tavily` are hidden. Hidden adapters can still be used by name, such as by the `web_search` tool.

To list only the adapters in your own config, leaving out the built-in ones:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      opts = {
        show_presets = false,
      },
    },
  },
})
```

## Setting a Proxy

To send requests through a proxy:

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
})
```

## Setup Examples

Some of these are illustrations rather than setups the plugin actively supports.

### Azure OpenAI

The `azure_openai` adapter has no default model, so set your deployment name:

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
  interactions = {
    chat = {
      adapter = "azure_openai",
    },
    inline = {
      adapter = "azure_openai",
    },
  },
})
```

### Copilot Free and Student

Copilot Free and Student plans only get models [through auto model selection](https://docs.github.com/en/copilot/reference/ai-models/supported-models#supported-ai-models-per-copilot-plan). The `copilot` adapter defaults to the `auto` model, so it works without any extra config.

### llama.cpp with `--reasoning-format deepseek`

To show llama.cpp's reasoning output in the chat buffer:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      ["llama.cpp"] = function()
        return require("codecompanion.adapters").extend("openai_compatible", {
          env = {
            url = "http://127.0.0.1:8080", -- replace with your llama.cpp instance
            api_key = "TERM",
            chat_url = "/v1/chat/completions",
          },
          handlers = {
            parse_message_meta = function(self, data)
              local extra = data.extra
              if extra and extra.reasoning_content then
                data.output.reasoning = { content = extra.reasoning_content }
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
  interactions = {
    chat = {
      adapter = "llama.cpp",
    },
    inline = {
      adapter = "llama.cpp",
    },
  },
})
```

### Ollama (remotely)

To connect to a remote Ollama server, set `OLLAMA_HOST`, the same variable the Ollama CLI uses:

```bash
export OLLAMA_HOST="http://192.168.1.100:11434"
```

Or set the URL on the adapter, with an API key sent in an `Authorization` header if the server needs one:

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
        })
      end,
    },
  },
})
```

### OpenAI Responses API

The `openai` adapter uses OpenAI's [Responses API](https://platform.openai.com/docs/api-reference/responses). To use the [Chat Completions API](https://platform.openai.com/docs/api-reference/chat) instead:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      adapter = "openai_legacy",
    },
    inline = {
      adapter = "openai_legacy",
    },
  },
})
```

The `openai` adapter sends `store = false`, so OpenAI doesn't [store](https://platform.openai.com/docs/api-reference/responses/create#responses-create-store) your responses.

### OpenRouter

The `openrouter` adapter supports:

- Explicit prompt caching for Anthropic models
- Server tools such as [web_fetch](https://openrouter.ai/docs/guides/features/server-tools/web-fetch) and [web_search](https://openrouter.ai/docs/guides/features/server-tools/web-search)
- Reasoning [effort](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens#reasoning-effort-level) levels
- [Presets](https://openrouter.ai/docs/guides/features/presets)
- [Provider routing](https://openrouter.ai/docs/guides/routing/provider-selection)

Tool use, vision and the available parameters depend on the model you select. Set them in your config, or for a single chat in the [debug window](/usage/chat-buffer/#debug-window):

::: code-group

```lua [Presets] {7}
require("codecompanion").setup({
  adapters = {
    http = {
      openrouter = function()
        return require("codecompanion.adapters").extend("openrouter", {
          schema = {
            preset = { default = "email-copywriter" },
          },
        })
      end,
    },
  },
})
```

```lua [Provider Routing] {7-13}
require("codecompanion").setup({
  adapters = {
    http = {
      openrouter = function()
        return require("codecompanion.adapters").extend("openrouter", {
          schema = {
            provider = {
              default = {
                allow_fallbacks = true,
                order = { "anthropic", "openai" },
                require_parameters = false,
              },
            },
          },
        })
      end,
    },
  },
})
```

:::

Each chat buffer sends its own `session_id` for [sticky sessions](https://openrouter.ai/docs/guides/best-practices/prompt-caching#using-session_id-for-sticky-sessions), which you can rename in the debug window. To fix it on the adapter instead:

```lua {6}
require("codecompanion").setup({
  adapters = {
    http = {
      openrouter_title_generation = function()
        return require("codecompanion.adapters").extend("openrouter", {
          opts = { session_id = "title_generation" },
        })
      end,
    },
  },
})
```

## Community Adapters

Adapters built by the community:

- [DashScope](https://github.com/olimorris/codecompanion.nvim/discussions/2239)
- [Fireworks.ai](https://github.com/olimorris/codecompanion.nvim/discussions/693)
- [InceptionLabs - Mercury 2](https://github.com/olimorris/codecompanion.nvim/discussions/2867)
- [Nvidia NIM](https://github.com/olimorris/codecompanion.nvim/discussions/2810)
- [Venice.ai](https://github.com/olimorris/codecompanion.nvim/discussions/972)
- [Vertex AI](https://github.com/viespejo/cc-adapter-vertex-ai.nvim)

Raise issues and questions about them in their threads in the [adapter discussions](https://github.com/olimorris/codecompanion.nvim/discussions?discussions_q=is%3Aopen+label%3A%22tip%3A+adapter%22).

<style scoped>
table td:first-child code {
  white-space: nowrap;
}
</style>
