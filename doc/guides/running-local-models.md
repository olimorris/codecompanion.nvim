---
description: "Run CodeCompanion against a local model in Neovim with Ollama, including choosing the model, connecting to another machine and using tools."
---

# Running Local Models

A local model keeps your code on your own machine and needs no API key. CodeCompanion ships with an `ollama` adapter, and can reach other local servers such as llama.cpp and LM Studio through `openai_compatible`.

This guide assumes [Ollama](https://ollama.com) is installed and running, and that you've pulled a model:

```
ollama pull qwen3:8b
```

## Pointing CodeCompanion at Ollama

Set the adapter and the model for each interaction you want to run locally:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      adapter = {
        name = "ollama",
        model = "qwen3:8b",
      },
    },
    inline = {
      adapter = {
        name = "ollama",
        model = "qwen3:8b",
      },
    },
  },
})
```

The model is the tag you see in `ollama list`. In the chat buffer, press `ga` to switch to any other model you've pulled.

> [!WARNING]
> **Image needed:** The `ga` picker in a chat buffer after choosing Ollama, listing the locally pulled models such as `qwen3:8b` and `gpt-oss:20b`

## Choosing the Model

**Always set a model.** If you set `adapter = "ollama"` on its own, CodeCompanion asks Ollama for your installed models and picks one of them, and which one it picks isn't predictable. With several models pulled, you can end up in a chat with the wrong one.

Set it per interaction, as above, or once on the adapter so every interaction uses it:

::: code-group

```lua [Per Interaction]
require("codecompanion").setup({
  interactions = {
    chat = {
      adapter = {
        name = "ollama",
        model = "qwen3-coder:30b",
      },
    },
    inline = {
      adapter = {
        name = "ollama",
        model = "qwen3:8b",
      },
    },
  },
})
```

```lua [On the Adapter]
require("codecompanion").setup({
  adapters = {
    http = {
      ollama = function()
        return require("codecompanion.adapters").extend("ollama", {
          schema = {
            model = {
              default = "qwen3:8b",
            },
          },
        })
      end,
    },
  },
  interactions = {
    chat = {
      adapter = "ollama",
    },
    inline = {
      adapter = "ollama",
    },
  },
})
```

:::

A model set on the interaction takes precedence over the adapter's default.

> [!IMPORTANT]
> When you use the table form, always include `model`. `adapter = { name = "ollama" }` on its own throws an error when you open a chat

## Running Ollama on Another Machine

The adapter connects to `http://localhost:11434` unless the `OLLAMA_HOST` environment variable is set, the same variable the Ollama CLI reads:

```bash
export OLLAMA_HOST="http://192.168.1.100:11434"
```

To set the URL in your config instead, or to send an API key to a server that sits behind authentication:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      ollama = function()
        return require("codecompanion.adapters").extend("ollama", {
          env = {
            url = "https://ollama.example.com",
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

`api_key` names an environment variable. See [environment variables](/configuration/adapters-http#environment-variables) for reading it from a command or password manager instead.

## Using Tools

Tools such as `@{files}` and `@{agent}` only work with models that support tool calling. CodeCompanion asks Ollama for each model's capabilities, and if `tools` isn't among them, the tool definitions aren't sent. The model then answers without calling anything. To check a model:

```
ollama show qwen3:8b
```

Models listing `tools` include `qwen3`, `qwen3-coder`, `gpt-oss`, `devstral` and `llama3.1`. Support alone isn't enough, though. Smaller models often call the wrong tool, pass malformed arguments or stop halfway through a task, so for `@{agent}` a model of 20B parameters or more is a sensible starting point. See [Tools](/usage/chat-buffer/agents-tools) for what each tool does.

### Models That Need One System Prompt

Adding tools puts several _system messages_ into the request, and some of them sit after your first message. Some chat templates reject this. Qwen3.5 on llama.cpp, for example, fails with `System message must be at the beginning`.

The `replace_main_system_prompt` option under `interactions.chat.tools.opts.system_prompt` removes one of these messages, but not all of them. To send a single system message at the top of every request, merge them in the adapter:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      ollama = function()
        local ollama = require("codecompanion.adapters.http.ollama")
        local adapter_utils = require("codecompanion.adapters.utils")

        return require("codecompanion.adapters").extend("ollama", {
          handlers = {
            form_messages = function(self, messages)
              return ollama.handlers.form_messages(self, adapter_utils.merge_system_messages(messages))
            end,
          },
        })
      end,
    },
  },
})
```

For an `openai_compatible` adapter, call `require("codecompanion.adapters.http.openai").handlers.form_messages` in the same way.

## Keeping It Fast

A local model is limited by your hardware, so these schema options are worth knowing:

| Option | Effect |
|---|---|
| `num_ctx` | Size of the context window Ollama loads the model with, in tokens. Larger costs more memory |
| `think` | Turns reasoning on or off. On by default for models that support it |
| `keep_alive` | How long Ollama keeps the model in memory after a request, such as `"30m"`. Ollama's default is 5 minutes |

Set them on the adapter:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      ollama = function()
        return require("codecompanion.adapters").extend("ollama", {
          schema = {
            num_ctx = {
              default = 32768,
            },
            think = {
              default = false,
            },
            keep_alive = {
              default = "30m",
            },
          },
        })
      end,
    },
  },
})
```

[Context management](/configuration/context-management) works out its default triggers as a percentage of the model's maximum context window, as reported by Ollama, not your `num_ctx`. If you set `num_ctx` lower than the maximum, use token counts instead:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      opts = {
        context_management = {
          editing = {
            trigger = 20000, -- tokens
          },
          compaction = {
            trigger = 26000, -- tokens
          },
        },
      },
    },
  },
})
```

Compaction also runs on the chat's model by default. To send it to a smaller one, see [Using a Cheaper Model for Background Tasks](/guides/background-model).

## Other Local Servers

llama.cpp, LM Studio, vLLM and similar servers speak the OpenAI API, so they connect through the `openai_compatible` adapter. See [Connecting an OpenAI-Compatible Provider](/guides/openai-compatible-providers) for the setup, and the [llama.cpp example](/configuration/adapters-http#llama-cpp-with-reasoning-format-deepseek) for showing its reasoning output in the chat buffer.

## Limitations

- Opening a chat asks Ollama for its models. If Ollama isn't running or can't be reached, you'll see an error, and each request waits up to 3 seconds before giving up
- Without a `model` set, the model CodeCompanion picks isn't predictable
- CodeCompanion doesn't merge system messages for you. Models whose templates need a single system message fail once tools are added, until you use the [workaround above](#models-that-need-one-system-prompt)
- Whether a model can use tools comes from Ollama. A model that reports `tools` can still be too small to use them reliably
