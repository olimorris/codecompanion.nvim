---
description: "Build your own HTTP adapter to connect CodeCompanion to any LLM."
---

# Extending with Adapters

An _adapter_ is the bridge between CodeCompanion and an LLM's API. It describes the endpoint, the headers and parameters to send, and how to turn CodeCompanion's messages into a request and the LLM's response back into text, reasoning and tool calls. The built-in adapters live in the [adapters directory](https://github.com/olimorris/codecompanion.nvim/tree/main/lua/codecompanion/adapters/http).

> [!TIP]
> If your LLM is "OpenAI compatible", extend the `openai_legacy` adapter or use `openai_compatible` instead of writing one from scratch. The [xAI](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/adapters/http/xai.lua) adapter does this

## The Interface

An HTTP adapter is a table with the following fields (abridged from `lua/codecompanion/adapters/http/init.lua`):

```lua
---@class CodeCompanion.HTTPAdapter
---@field name string The name of the adapter e.g. "openai"
---@field formatted_name string The formatted name of the adapter e.g. "OpenAI"
---@field roles table The mapping of roles in the config to the LLM's defined roles
---@field features table The features that the adapter supports
---@field url string The URL of the LLM to connect to
---@field env? table Environment variables which can be referenced in the parameters
---@field env_replaced? table Replacement of environment variables with their actual values
---@field headers table The headers to pass to the request
---@field parameters table The parameters to pass to the request
---@field body table Additional body parameters to pass to the request
---@field raw? table Any additional curl arguments to pass to the request
---@field opts? table Additional options for the adapter
---@field handlers CodeCompanion.HTTPAdapter.Handlers Functions which link the output from the request to CodeCompanion
---@field schema table Set of parameters for the LLM that the user can customise in the chat buffer
```

The fields up to `handlers` describe the API and are passed to curl. The `handlers` do the real work, translating between CodeCompanion and the LLM.

`roles` maps CodeCompanion's roles to the LLM's. Messages reach your handlers with their roles already mapped:

```lua
roles = {
  llm = "assistant",
  user = "user",
  tool = "tool",
},
```

`opts` holds flags such as `stream`, `tools`, `vision` and `documents`. `features.tokens = true` is required for the `parse_tokens` handler to be called.

## Environment Variables

APIs need values injected into different parts of the request. Azure OpenAI puts the endpoint, deployment and API version in the URL, whilst OpenAI takes the API key in an `Authorization` header. Declare them in `env` and reference them with `${}`:

```lua
url = "${endpoint}/openai/deployments/${deployment}/chat/completions?api-version=${api_version}",
env = {
  api_key = "AZURE_OPENAI_API_KEY",
  endpoint = "AZURE_OPENAI_ENDPOINT",
  api_version = "2024-06-01",
  deployment = "schema.model.default",
},
headers = {
  ["Content-Type"] = "application/json",
  ["api-key"] = "${api_key}",
},
```

Variables are replaced in the `url`, `headers`, `parameters` and `raw` fields on every request. Each value is resolved in this order:

| Value | Example | Resolves to |
| --- | --- | --- |
| `cmd:` prefix | `"cmd:op read op://personal/Gemini_API/credential --no-newline"` | The command's output, with trailing whitespace removed |
| `file:` prefix | `"file:~/.secrets/gemini"` | The file's contents, with trailing whitespace removed |
| Environment variable | `"GEMINI_API_KEY"` | The variable's value, if it's set |
| Function | `function(self) return os.getenv("GEMINI_API_KEY") end` | The function's return value, called with the adapter |
| Schema path | `"schema.model.default"` | The value at that path on the adapter |
| Anything else | `"2024-06-01"` | The string, unchanged |

Commands time out after 20 seconds. This can be changed with:

```lua
require("codecompanion").setup({
  adapters = {
    opts = {
      cmd_timeout = 20000, -- milliseconds
    },
  },
})
```

> [!WARNING]
> A schema path returns the raw value. If `schema.model.default` is a function, use a function in `env` instead

## Handlers

Handlers are grouped into four tables. Each one takes `self` and a single `args` table, so new fields can be added without breaking your adapter:

```lua
handlers = {
  lifecycle = {
    setup = function(self) end,
    on_exit = function(self, args) end,
    teardown = function(self) end,
  },
  request = {
    build_parameters = function(self, args) end,
    build_messages = function(self, args) end,
    build_tools = function(self, args) end,
    build_structured_output = function(self, args) end,
    build_reasoning = function(self, args) end,
    build_body = function(self, args) end,
  },
  response = {
    parse_chat = function(self, args) end,
    parse_inline = function(self, args) end,
    parse_tokens = function(self, args) end,
    parse_meta = function(self, args) end,
  },
  tools = {
    format_calls = function(self, args) end,
    format_response = function(self, args) end,
  },
}
```

All of them are optional. Every built-in adapter has its own tests, which show how each one handles the API's output.

### Lifecycle

| Handler | `args` | Description |
| --- | --- | --- |
| `setup` | | Run before the request is sent and before environment variables are resolved. Return `false` to cancel the request |
| `on_exit` | `data` | Run when the request completes, or with no `data` when the user stops it |
| `teardown` | | Run last, after `on_exit` |

### Request

Except for `build_reasoning`, their return values are merged into the request body:

| Handler | `args` | Description |
| --- | --- | --- |
| `build_parameters` | `params`, `messages` | Set the request's parameters |
| `build_messages` | `messages` | Format the messages for the LLM |
| `build_tools` | `tools` | Convert CodeCompanion's tool schemas into the LLM's format |
| `build_structured_output` | `schema` | Convert a structured output schema into the LLM's format |
| `build_reasoning` | `data` | Combine the streamed reasoning chunks into one, to store on the LLM's message |
| `build_body` | `payload` | Add anything else to the body |

### Response

| Handler | `args` | Description |
| --- | --- | --- |
| `parse_chat` | `data`, `tools` | Parse a response for the chat buffer, writing any tool calls into `tools` |
| `parse_inline` | `data`, `context` | Parse a response for the inline interaction |
| `parse_tokens` | `data` | Return the token count from a response |
| `parse_meta` | `data` | Process non-standard fields that `parse_chat` returns in `extra` |

### Tools

| Handler | `args` | Description |
| --- | --- | --- |
| `format_calls` | `tools` | Format the LLM's tool calls for the next request |
| `format_response` | `tool_call`, `output` | Format a tool's output as a message for the LLM |

## Building the Handlers

The examples below build the main handlers for OpenAI's Chat Completions API, as in the `openai_legacy` adapter. Put this at the top of your adapter:

```lua
local adapter_utils = require("codecompanion.adapters.utils")
local log = require("codecompanion.utils.log")
```

### `build_messages`

OpenAI expects a `messages` array of `role` and `content`:

```sh
curl https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-4.1",
    "messages": [
      {
        "role": "user",
        "content": "Explain Ruby in two words"
      }
    ]
  }'
```

CodeCompanion passes the chat buffer's messages in `args.messages`, each with at least a `role` and `content`:

```lua
{
  {
    role = "user",
    content = "Explain Ruby in two words",
  },
}
```

That's already the right shape, so the handler returns them as they are:

```lua
handlers = {
  request = {
    build_messages = function(self, args)
      return { messages = args.messages }
    end,
  },
}
```

### `build_parameters`

OpenAI needs no extra parameters, so this returns them unchanged:

```lua
handlers = {
  request = {
    build_parameters = function(self, args)
      return args.params
    end,
  },
}
```

### `parse_chat`

A streamed response arrives in chunks, and CodeCompanion calls `parse_chat` with each one in `args.data`:

```txt
data: {"id":"chatcmpl-90DdmqMKOKpqFemxX0OhTVdH042gu","object":"chat.completion.chunk","created":1709839462,"model":"gpt-4.1","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}

data: {"id":"chatcmpl-90DdmqMKOKpqFemxX0OhTVdH042gu","object":"chat.completion.chunk","created":1709839462,"model":"gpt-4.1","choices":[{"index":0,"delta":{"content":"Programming"},"finish_reason":null}]}

data: [DONE]
```

Each chunk is prefixed with `data: `, so it isn't valid JSON. `adapter_utils.clean_streamed_data` strips the prefix, and `luanil = { object = true }` keeps `null` values as `nil`:

```lua
handlers = {
  response = {
    parse_chat = function(self, args)
      if not args.data or args.data == "" then
        return nil
      end

      local data = adapter_utils.clean_streamed_data(args.data)
      local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })
      if not ok or not json.choices or #json.choices == 0 then
        return nil
      end

      local delta = json.choices[1].delta
      return {
        status = "success",
        output = {
          role = delta.role,
          content = delta.content,
        },
      }
    end,
  },
}
```

**`parse_chat` must return a table with `status` and `output`**. Return `nil` for anything it can't parse, such as `[DONE]` or an error, and leave errors to `on_exit`.

To show reasoning, add `output.reasoning = { content = "..." }`.

### `parse_meta`

Some OpenAI-compatible providers, such as DeepSeek and OpenRouter, add non-standard fields to the [`message`](https://platform.openai.com/docs/api-reference/chat/object#chat-object-choices-message) or [`delta`](https://platform.openai.com/docs/api-reference/chat-streaming/streaming#chat_streaming-streaming-choices-delta) object. The OpenAI-based adapters return these in an `extra` table from `parse_chat`, and `parse_meta` is called whenever `extra` is present.

DeepSeek streams its reasoning in `delta.reasoning_content`. To move it into the reasoning output:

```lua
handlers = {
  response = {
    parse_meta = function(self, args)
      local data = args.data
      if data.extra.reasoning_content then
        data.output.reasoning = { content = data.extra.reasoning_content }
        -- An empty string is treated as a normal response
        if data.output.content == "" then
          data.output.content = nil
        end
      end
      return data
    end,
  },
}
```

Always return `data`. Setting `output.content` to `nil` is only needed when streaming and can cause problems without it.

### `parse_inline`

The inline interaction doesn't stream, so `args.data` is the whole response, with the JSON in `args.data.body`. Return the text to write into the buffer:

```lua
handlers = {
  response = {
    parse_inline = function(self, args)
      if not args.data or args.data == "" then
        return nil
      end

      local ok, json = pcall(vim.json.decode, args.data.body, { luanil = { object = true } })
      if not ok then
        return { status = "error", output = json }
      end

      return { status = "success", output = json.choices[1].message.content }
    end,
  },
}
```

`args.context` holds details of the buffer that started the request.

### `on_exit`

Errors from a streaming endpoint are hard to parse, as they arrive across several `data:` lines. `on_exit` receives the final response instead:

```lua
{
  body = '{\n    "error": {\n        "message": "Incorrect API key provided: sk-F18b****XdwS.",\n        "type": "invalid_request_error",\n        "param": null,\n        "code": "invalid_api_key"\n    }\n}',
  exit = 0,
  headers = { "date: Thu, 03 Oct 2024 08:05:32 GMT" },
  status = 401,
}
```

That's easier to work with:

```lua
handlers = {
  lifecycle = {
    on_exit = function(self, args)
      if args.data and args.data.status >= 400 then
        log:error("Error: %s", args.data.body)
      end
    end,
  },
}
```

`log:error` writes to the log file and notifies the user.

### `setup` and `teardown`

`setup` runs before environment variables are resolved, which is why the Copilot adapter uses it to fetch a token. It runs on a copy of the adapter made for each request, so changes don't carry over to the next one:

```lua
handlers = {
  lifecycle = {
    setup = function(self)
      if self.opts.stream then
        self.parameters.stream = true
      end
      return true
    end,
    teardown = function(self) end,
  },
}
```

### Utilities

Many "OpenAI compatible" endpoints have quirks:

- System messages must come first (`anthropic`, `deepseek`)
- System messages must be a single message (`anthropic`, `deepseek`)
- Messages must alternate between user and LLM (`deepseek`)

The [adapter utilities](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/adapters/utils/init.lua), such as `merge_system_messages` and `merge_messages`, handle these. The built-in adapters are the best reference for how to use them.

## Tools

To support [function calling](https://platform.openai.com/docs/guides/function-calling?api-mode=chat), set `opts.tools = true` and have `parse_chat` write tool calls into `args.tools`. Then add:

- **`build_tools`** - converts CodeCompanion's tool schemas into the LLM's format
- **`format_calls`** - [formats](https://platform.openai.com/docs/guides/function-calling?api-mode=chat#handling-function-calls) the LLM's tool calls for the next request
- **`format_response`** - formats a tool's output as a message for the chat buffer's message history

```lua
handlers = {
  request = {
    build_tools = function(self, args)
      if not self.opts.tools or not args.tools then
        return nil
      end

      local transformed = {}
      for _, tool in pairs(args.tools) do
        for _, schema in pairs(tool) do
          table.insert(transformed, schema)
        end
      end
      return { tools = transformed }
    end,
  },
  tools = {
    format_calls = function(self, args)
      return args.tools
    end,
    format_response = function(self, args)
      return {
        role = self.roles.tool or "tool",
        tools = {
          call_id = adapter_utils.pairing_id(args.tool_call),
          name = args.tool_call["function"].name,
        },
        content = args.output,
        opts = { visible = false },
      }
    end,
  },
}
```

Many LLMs claim to follow OpenAI's function calling standard but still need adjustments to work.

## Schema

The `schema` table describes the LLM's settings. With `display.chat.show_settings = true`, they appear at the top of the chat buffer for the user to edit.

From the `openai_legacy` adapter:

```lua
schema = {
  model = {
    order = 1,
    mapping = "parameters",
    type = "enum",
    desc = "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
    default = "gpt-4.1",
    choices = {
      ["gpt-4.1"] = {
        formatted_name = "GPT 4.1",
        meta = { context_window = 1047576 },
        opts = { has_vision = true, can_form_structured_outputs = true },
      },
      ["o3-mini-2025-01-31"] = {
        formatted_name = "o3 Mini",
        opts = { can_reason = true, can_form_structured_outputs = true },
      },
      "gpt-4",
      "gpt-3.5-turbo",
    },
  },
},
```

| Key | Description |
| --- | --- |
| `order` | Position in the chat buffer's settings |
| `mapping` | Where in the adapter the value goes, such as `parameters` |
| `type` | One of `string`, `number`, `integer`, `boolean`, `enum`, `list` or `map` |
| `desc` | Shown as virtual text when the cursor is on the setting |
| `default` | The default value, or a function that receives the adapter |
| `choices` | The allowed values for an `enum`, or a function that returns them |
| `optional` | Allow the value to be `nil` |
| `enabled` | A function that receives the adapter and returns whether the setting applies |
| `validate` | A function that returns whether the value is valid, and an error message if not |

A choice can be a plain string, or a table with a `formatted_name`, `meta` and `opts` for your handlers to read at runtime.

A setting can depend on the model:

```lua
temperature = {
  order = 2,
  mapping = "parameters",
  type = "number",
  default = 0,
  enabled = function(self)
    local model = require("codecompanion.adapters.utils").resolve_model(self)
    return model ~= nil and not vim.startswith(model, "o1")
  end,
  validate = function(n)
    return n >= 0 and n <= 2, "Must be between 0 and 2"
  end,
  desc = "What sampling temperature to use, between 0 and 2.",
},
```

`o1` models don't accept a temperature, so `enabled` leaves it out of their requests.

> [!IMPORTANT]
> `schema.model.default` can be a function. Use `resolve_model` from `codecompanion.adapters.utils` to read it as a string

Some APIs, such as OpenAI's [Responses API](https://platform.openai.com/docs/api-reference/responses/create?api-mode=responses), nest parameters:

```bash
curl https://api.openai.com/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "o3-mini",
    "input": "How much wood would a woodchuck chuck?",
    "reasoning": {
      "effort": "high"
    }
  }'
```

Use dot notation in the key to nest the value:

```lua
["reasoning.effort"] = {
  mapping = "parameters",
  type = "string",
  -- ...
},
```

## Legacy Handlers

Adapters written with the older flat handlers still work, and their handlers still take positional arguments. CodeCompanion detects the format and maps the old names to the new ones. From v20.0.0, the new handlers take a single `args` table.

| Old | New |
| --- | --- |
| `setup`, `on_exit`, `teardown` | `lifecycle.setup`, `lifecycle.on_exit`, `lifecycle.teardown` |
| `form_parameters`, `form_messages`, `form_tools` | `request.build_parameters`, `request.build_messages`, `request.build_tools` |
| `form_structured_output`, `form_reasoning`, `set_body` | `request.build_structured_output`, `request.build_reasoning`, `request.build_body` |
| `chat_output`, `inline_output`, `tokens` | `response.parse_chat`, `response.parse_inline`, `response.parse_tokens` |
| `parse_message_meta` | `response.parse_meta` |
| `tools.format_tool_calls`, `tools.output_response` | `tools.format_calls`, `tools.format_response` |

**An adapter is treated as the new format if it has a `lifecycle`, `request` or `response` table**, so don't mix the two.

To migrate, move each handler into its group and read its arguments from `args`:

::: code-group

```lua [Old]
handlers = {
  setup = function(self) end,
  form_parameters = function(self, params, messages) end,
  form_messages = function(self, messages) end,
  chat_output = function(self, data, tools) end,
  on_exit = function(self, data) end,
  teardown = function(self) end,
  tools = {
    format_tool_calls = function(self, tools) end,
    output_response = function(self, tool_call, output) end,
  },
}
```

```lua [New]
handlers = {
  lifecycle = {
    setup = function(self) end,
    on_exit = function(self, args) end,
    teardown = function(self) end,
  },
  request = {
    build_parameters = function(self, args) end,
    build_messages = function(self, args) end,
  },
  response = {
    parse_chat = function(self, args) end,
  },
  tools = {
    format_calls = function(self, args) end,
    format_response = function(self, args) end,
  },
}
```

:::
