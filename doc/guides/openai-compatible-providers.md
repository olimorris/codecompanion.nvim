---
description: "Connect CodeCompanion to any provider that speaks the OpenAI API, such as a company gateway, LM Studio or vLLM, without writing an adapter."
---

# Connecting an OpenAI-Compatible Provider

Many providers, self-hosted servers and company gateways accept the same requests as OpenAI's Chat Completions API. CodeCompanion's `openai_compatible` adapter speaks that API, so you only need to give it a URL, a key and a name.

## Adding the Adapter

Extend `openai_compatible` under a name of your own. The name is what you pick in the chat buffer and set in your config:

::: code-group

```lua [Company Gateway]
require("codecompanion").setup({
  adapters = {
    http = {
      acme_gateway = function()
        return require("codecompanion.adapters").extend("openai_compatible", {
          formatted_name = "Acme Gateway",
          env = {
            url = "https://llm-gateway.acme.internal",
            api_key = "ACME_GATEWAY_KEY",
          },
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

```lua [LM Studio]
require("codecompanion").setup({
  adapters = {
    http = {
      lm_studio = function()
        return require("codecompanion.adapters").extend("openai_compatible", {
          formatted_name = "LM Studio",
          env = {
            url = "http://localhost:1234",
            api_key = "lm-studio",
          },
        })
      end,
    },
  },
})
```

```lua [vLLM]
require("codecompanion").setup({
  adapters = {
    http = {
      vllm = function()
        return require("codecompanion.adapters").extend("openai_compatible", {
          formatted_name = "vLLM",
          env = {
            url = "http://gpu-box.local:8000",
            api_key = "VLLM_API_KEY",
          },
        })
      end,
    },
  },
})
```

:::

The adapter builds its URLs from four `env` keys:

| Key | Default | Purpose |
|---|---|---|
| `url` | `http://localhost:11434` | The server's base URL, without `/v1` |
| `chat_url` | `/v1/chat/completions` | Appended to `url` for every chat and inline request |
| `models_endpoint` | `/v1/models` | Appended to `url` to list the available models |
| `api_key` | `OPENAI_API_KEY` | Sent as `Authorization: Bearer <key>` |

If a provider gives you a base URL that ends in `/v1`, such as `https://api.tsubasa.sh/v1`, drop the `/v1` from `url`. The default `chat_url` and `models_endpoint` already include it.

`formatted_name` is what appears in the chat buffer's header and the [debug window](/usage/chat-buffer/#debug-window). Without it, every adapter built on `openai_compatible` is labelled "OpenAI Compatible".

## Choosing the Model

If you don't set a model, the adapter asks `models_endpoint` for the list of models and uses the first one it returns. The list is cached for 30 minutes, set by `adapters.http.opts.cache_models_for` in seconds.

Some providers don't serve a model list. If yours returns a 404, or lists models you can't use, set both the default and the choices yourself so the endpoint is never called:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      tsubasa = function()
        return require("codecompanion.adapters").extend("openai_compatible", {
          formatted_name = "Tsubasa",
          env = {
            url = "https://api.tsubasa.sh",
            api_key = "TSUBASA_API_KEY",
          },
          schema = {
            model = {
              default = "tsubasa-fast",
              choices = { "tsubasa-fast", "tsubasa-pro" },
            },
          },
        })
      end,
    },
  },
})
```

Setting only `default` picks the model, but the endpoint is still called when you open the model picker.

## Keeping the API Key Out of Your Config

`api_key` is resolved when a request is sent, so the key itself never needs to be in your config. Give it the name of an environment variable, a command or a file:

::: code-group

```lua [Environment Variable]
require("codecompanion").setup({
  adapters = {
    http = {
      acme_gateway = function()
        return require("codecompanion.adapters").extend("openai_compatible", {
          env = {
            url = "https://llm-gateway.acme.internal",
            api_key = "ACME_GATEWAY_KEY",
          },
        })
      end,
    },
  },
})
```

```lua [Command]
require("codecompanion").setup({
  adapters = {
    http = {
      acme_gateway = function()
        return require("codecompanion.adapters").extend("openai_compatible", {
          env = {
            url = "https://llm-gateway.acme.internal",
            api_key = "cmd:op read op://work/Acme Gateway/credential --no-newline",
          },
        })
      end,
    },
  },
})
```

```lua [File]
require("codecompanion").setup({
  adapters = {
    http = {
      acme_gateway = function()
        return require("codecompanion.adapters").extend("openai_compatible", {
          env = {
            url = "https://llm-gateway.acme.internal",
            api_key = "file:~/.config/acme/gateway_key",
          },
        })
      end,
    },
  },
})
```

:::

A value that isn't an environment variable, a `cmd:` or a `file:` is sent as it is. That's why `api_key = "lm-studio"` works for a local server that ignores the key. Commands time out after 20 seconds, set by `adapters.opts.cmd_timeout` in milliseconds. See [environment variables](/configuration/adapters-http#environment-variables) for every form `env` accepts.

> [!IMPORTANT]
> If you don't set `api_key`, the adapter sends the value of `OPENAI_API_KEY`. Set it to something else so your OpenAI key isn't sent to another provider

## Using It in Chat and Inline

To make your adapter the default:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      adapter = "acme_gateway",
    },
    inline = {
      adapter = {
        name = "acme_gateway",
        model = "gpt-4.1-mini",
      },
    },
  },
})
```

Every adapter you define under `adapters.http` is listed when you press `ga` in the chat buffer, alongside the presets. To show only your own, set `adapters.http.opts.show_presets = false`. See [Configuring HTTP Adapters](/configuration/adapters-http#hiding-adapters).

## When the Provider Differs

### Extra Headers

`headers` are merged with the adapter's own, so `Content-Type` and `Authorization` stay in place. Headers can reference any `env` key with `${key}`:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      acme_gateway = function()
        return require("codecompanion.adapters").extend("openai_compatible", {
          env = {
            url = "https://llm-gateway.acme.internal",
            api_key = "ACME_GATEWAY_KEY",
            team_id = "ACME_TEAM_ID",
          },
          headers = {
            ["X-Team-Id"] = "${team_id}",
          },
        })
      end,
    },
  },
})
```

### A Different Endpoint Path

Gateways often mount the API under a prefix. Change `chat_url` and `models_endpoint` to match:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      acme_gateway = function()
        return require("codecompanion.adapters").extend("openai_compatible", {
          env = {
            url = "https://api.acme.com",
            api_key = "ACME_GATEWAY_KEY",
            chat_url = "/llm/openai/v1/chat/completions",
            models_endpoint = "/llm/openai/v1/models",
          },
        })
      end,
    },
  },
})
```

### No Streaming, Tools or Images

The adapter assumes the server supports streaming, tool calls and images. Turn off whatever yours doesn't:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      acme_gateway = function()
        return require("codecompanion.adapters").extend("openai_compatible", {
          env = {
            url = "https://llm-gateway.acme.internal",
            api_key = "ACME_GATEWAY_KEY",
          },
          opts = {
            stream = false,
            tools = false,
            vision = false,
          },
        })
      end,
    },
  },
})
```

With `tools = false`, tool definitions are left out of the request, so the LLM never sees `@{files}` or any other tool. With `vision = false`, images added with [/file](/usage/chat-buffer/slash-commands#file) aren't added to the chat.

### The Responses API

If your provider or gateway serves OpenAI's [Responses API](https://platform.openai.com/docs/api-reference/responses) at `/v1/responses`, extend `openai` instead. CodeCompanion uses it to carry a model's reasoning between turns and for server-side compaction. It has no `env.url`, so set the full `url`:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      acme_responses = function()
        return require("codecompanion.adapters").extend("openai", {
          formatted_name = "Acme Gateway (Responses)",
          url = "https://llm-gateway.acme.internal/v1/responses",
          env = {
            api_key = "ACME_GATEWAY_KEY",
          },
        })
      end,
    },
  },
})
```

## When You Need a Custom Adapter

"OpenAI-compatible" sometimes only means close. The HAWKI API, for example, expects the model and messages wrapped in a `payload` object, and rejects the request with a 422 until they are. When a provider changes the shape of the request or the response, you need your own handlers. See [Extending with Adapters](/extending/adapters).

To see exactly what's being sent, set `opts.log_level = "DEBUG"` and send a message. The log records the path of each request body, and at that level the file is kept on disk. `:checkhealth codecompanion` shows where the log file is.

## Limitations

- Every adapter built on `openai_compatible` shares one model cache. If you define two, the second can be offered the first server's models until the cache expires, so set `schema.model.default` and `choices` on each
- `opts` apply to the whole adapter, not per model. To mix models that do and don't support tools on one server, define an adapter for each

See [Choosing an Adapter](/guides/choosing-an-adapter) to compare this with the built-in adapters, or [Running Local Models](/guides/running-local-models) for Ollama.
