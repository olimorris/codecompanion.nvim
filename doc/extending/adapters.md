---
description: Learn how to create your own adapters in CodeCompanion
---

# Creating Adapters

> [!TIP]
> Does your LLM state that it is "OpenAI Compatible"? If so, good news, you can extend from the `openai` adapter or use the `openai_compatible` one. Something we did with the [xAI](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/adapters/http/xai.lua) adapter

In CodeCompanion, adapters are interfaces that act as a bridge between the plugin's functionality and an LLM. All adapters must follow the interface, below.

This guide is intended to serve as a reference for anyone who wishes to contribute an adapter to the plugin or understand the inner workings of existing adapters.

The plugin's in-built adapters can be found [here](https://github.com/olimorris/codecompanion.nvim/tree/main/lua/codecompanion/adapters).

## The Interface

Let's take a look at the interface of an adapter as per the `adapter.lua` file:

```lua
---@class CodeCompanion.HTTPAdapter
---@field name string The name of the adapter e.g. "openai"
---@field formatted_name string The formatted name of the adapter e.g. "OpenAI"
---@field roles table The mapping of roles in the config to the LLM's defined roles
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

Everything up to the handlers should be self-explanatory. We're simply providing details of the LLM's API to the curl library and executing the request. The real intelligence of the adapter comes from the handlers table which is a set of functions which bridge the functionality of the plugin to the LLM.

## Handler Structure

As of v17.27.0, handlers are organized into a nested structure that provides clear separation of concerns:

```lua
handlers = {
  -- Lifecycle hooks (side effects and initialization)
  lifecycle = {
    setup = function(self) end,      -- Called before request is sent
    on_exit = function(self, data) end,  -- Called after request completes
    teardown = function(self) end,   -- Called last, after on_exit
  },

  -- Request builders (pure transformations)
  request = {
    build_parameters = function(self, params, messages) end,  -- Build request parameters
    build_messages = function(self, messages) end,            -- Format messages for LLM
    build_tools = function(self, tools) end,                  -- Transform tool schemas
    build_reasoning = function(self, messages) end,           -- Build reasoning parameters
    build_body = function(self, data) end,                    -- Set additional body parameters
  },

  -- Response parsers (pure transformations)
  response = {
    parse_chat = function(self, data, tools) end,       -- Parse chat response
    parse_inline = function(self, data, context) end,   -- Parse inline response
    parse_tokens = function(self, data) end,            -- Extract token count
  },

  -- Tool handlers (grouped functionality)
  tools = {
    format_calls = function(self, tools) end,                          -- Format tool calls for request
    format_response = function(self, tool_call, output) end,           -- Format tool response for LLM
  },
}
```

> [!NOTE]
> **Backwards Compatibility**: The old flat handler structure is still supported. Adapters using the old format (e.g., `form_parameters`, `form_messages`, `chat_output`) will continue to work. The plugin automatically detects and maps old handler names to the new structure.

## Environment Variables

When building an adapter, you'll need to inject variables into different parts of the adapter class. If we take the [Google Gemini](https://github.com/google-gemini/cookbook/blob/main/quickstarts/rest/Streaming_REST.ipynb) endpoint as an example, we need to inject the model and API key variables into the URL of `https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?alt=sse&key=${api_key}`. Whereas with [OpenAI](https://platform.openai.com/docs/api-reference/authentication), we need an `Authorization` http header to contain our API key.

Let's take a look at the `env` table from the Google Gemini adapter that comes with the plugin:

```lua
url = "https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?alt=sse&key=${api_key}",
env = {
  api_key = "GEMINI_API_KEY",
  model = "schema.model.default",
},
```

The key `api_key` represents the name of the variable which can be injected in the adapter via the `${}` notation, and the value can represent one of:

- A command to execute on the user's system
- An environment variable from the user's system
- A function to be executed at runtime
- A path to an item in the adapter's schema table
- A plain text value

> [!NOTE]
> Environment variables can be injected into the `url`, `headers` and `parameters` fields of the adapter class at runtime

**Commands**

An environment variable can be obtained from running a command on a user's system. This can be accomplished by prefixing the value with `cmd:` such as:

```lua
env = {
  api_key = "cmd:op read op://personal/Gemini_API/credential --no-newline",
},
```

In this example, we're running the `op read` command to get a credential from 1Password.

**Environment Variable**

An environment variable can also be obtained by using lua's `os.getenv` function. Simply enter the name of the variable as a string such as:

```lua
env = {
  api_key = "GEMINI_API_KEY",
},
```

**Functions**

An environment variable can also be resolved via the use of a function such as:

```lua
env = {
  api_key = function()
    return os.getenv("GEMINI_API_KEY")
  end,
},
```

**Schema Values**

An environment variable can also be resolved by entering the path to a value in a table on the adapter class. For example:

```lua
env = {
  model = "schema.model.default",
},
```

In this example, we're getting the value of a user's chosen model from the schema table on the adapter.

## Handlers

The handlers table is organized into four main categories:

### Lifecycle Handlers

These handlers manage side effects and initialization:

- `lifecycle.setup` - Called before the request is sent and before environment variables are set. Must return a boolean to indicate success
- `lifecycle.on_exit` - Called after the request completes. Useful for handling errors
- `lifecycle.teardown` - Called last, after `on_exit`

### Request Handlers

These handlers transform data for the LLM request:

- `request.build_parameters` - Set the parameters of the request
- `request.build_messages` - Format the messages array for the LLM
- `request.build_tools` - Transform tool schemas for the LLM
- `request.build_reasoning` - Build reasoning parameters (for models that support it)
- `request.build_body` - Set additional body parameters

### Response Handlers

These handlers parse LLM responses:

- `response.parse_chat` - Format chat output for the chat buffer
- `response.parse_inline` - Format output for inline insertion
- `response.parse_tokens` - Extract token count from the response
- `response.parse_extra` - Process non-standard fields in the response (currently only supported by OpenAI-based adapters)

### Tool Handlers

These handlers manage tool/function calling:

- `tools.format_calls` - Format tool calls for inclusion in the request
- `tools.format_response` - Format tool responses for the LLM

> [!TIP]
> All of the adapters in the plugin come with their own tests. These serve as a great reference to understand how they're working with the output of the API

### OpenAI's API Output

If we reference the OpenAI [documentation](https://platform.openai.com/docs/guides/text-generation/chat-completions-api) we can see that they require the messages to be in an array which consists of `role` and `content`:

```sh
curl https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-4-0125-preview",
    "messages": [
      {
        "role": "user",
        "content": "Explain Ruby in two words"
      }
    ]
  }'
```

### Chat Buffer Output

The chat buffer, which is structured like:

```markdown
## Me

Explain Ruby in two words
```

results in the following output:

```lua
{
  {
    role = "user",
    content = "Explain Ruby in two words"
  }
}
```

### `request.build_messages`

The chat buffer's output is passed to this handler in the form of the `messages` parameter. So we can just output this as part of a messages table:

```lua
handlers = {
  request = {
    build_messages = function(self, messages)
      return { messages = messages }
    end,
  },
}
```

### `response.parse_chat`

Now let's look at how we format the output from OpenAI. Running that request results in:

```txt
data: {"id":"chatcmpl-90DdmqMKOKpqFemxX0OhTVdH042gu","object":"chat.completion.chunk","created":1709839462,"model":"gpt-4-0125-preview","system_fingerprint":"fp_70b2088885","choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}]}
```

```txt
data: {"id":"chatcmpl-90DdmqMKOKpqFemxX0OhTVdH042gu","object":"chat.completion.chunk","created":1709839462,"model":"gpt-4-0125-preview","system_fingerprint":"fp_70b2088885","choices":[{"index":0,"delta":{"content":"Programming"},"logprobs":null,"finish_reason":null}]}
```

```txt
data: {"id":"chatcmpl-90DdmqMKOKpqFemxX0OhTVdH042gu","object":"chat.completion.chunk","created":1709839462,"model":"gpt-4-0125-preview","system_fingerprint":"fp_70b2088885","choices":[{"index":0,"delta":{"content":" language"},"logprobs":null,"finish_reason":null}]},
```

```txt
data: [DONE]
```

> [!IMPORTANT]
> Note that the `parse_chat` handler requires a table containing `status` and `output` to be returned.

Remember that we're streaming from the API so the request comes through in batches. Thankfully the `http.lua` file handles this and we just have to handle formatting the output into the chat buffer.

The first thing to note with streaming endpoints is that they don't return valid JSON. In this case, the output is prefixed with `data: `. CodeCompanion comes with some handy utility functions to work with this:

```lua
-- Put this at the top of your adapter
local utils = require("codecompanion.utils.adapters")

handlers = {
  response = {
    parse_chat = function(self, data)
      data = utils.clean_streamed_data(data)
    end,
  },
}
```

> [!IMPORTANT]
> The data passed to the `parse_chat` handler is the response from OpenAI

We can then decode the JSON using native vim functions:

```lua
handlers = {
  response = {
    parse_chat = function(self, data)
      data = utils.clean_streamed_data(data)
      local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })
    end,
  },
}
```

We want to include any nil values so we pass in `luanil = { object = true }`.

Examining the output of the API, we see that the streamed data is stored in a `choices[1].delta` table. That's easy to pickup:

```lua
handlers = {
  response = {
    parse_chat = function(self, data)
      ---
      local delta = json.choices[1].delta
    end,
  },
}
```

and we can then access the new streamed data that we want to write into the chat buffer, with:

```lua
handlers = {
  response = {
    parse_chat = function(self, data)
      local output = {}
      ---
      local delta = json.choices[1].delta

      if delta.content then
        output.content = delta.content
        output.role = delta.role or nil
      end
    end,
  },
}
```

And then we can return the output in the following format:

```lua
handlers = {
  response = {
    parse_chat = function(self, data)
      --
      return {
        status = "success",
        output = output,
      }
    end,
  },
}
```

Now if we put it all together, and put some checks in place to make sure that we have data in our response:

```lua
handlers = {
  response = {
    parse_chat = function(self, data)
      local output = {}

      if data and data ~= "" then
        data = utils.clean_streamed_data(data)
        local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

        local delta = json.choices[1].delta

        if delta.content then
          output.content = delta.content
          output.role = delta.role or nil

          return {
            status = "success",
            output = output,
          }
        end
      end
    end,
  },
}
```

### `response.parse_extra`

Some OpenAI-compatible API providers like deepseek, Gemini and OpenRouter implement a superset of the standard specification, and provide reasoning tokens/summaries within their response.
The non-standard fields in the [`message` (non-streaming)](https://platform.openai.com/docs/api-reference/chat/object#chat-object-choices-message) or [`delta` (streaming)](https://platform.openai.com/docs/api-reference/chat-streaming/streaming#chat_streaming-streaming-choices-delta) object are captured by the OpenAI adapter and can be used to extract the reasoning.

For example, the DeepSeek API provides the reasoning tokens in the `delta.reasoning_content` field.
We can therefore use the following `parse_extra` handler to extract the reasoning tokens and put them into the appropriate output fields: 

```lua
handlers = {
  response = {
    ---@param self CodeCompanion.HTTPAdapter
    --- `data` is the output of the `parse_chat` handler
    ---@param data {status: string, output: {role: string?, content: string?}, extra: table}
    ---@return {status: string, output: {role: string?, content: string?, reasoning:{content: string?}?}}
    parse_extra = function(self, data)
      local extra = data.extra
      if extra.reasoning_content then
        -- codecompanion expect the reasoning tokens in this format
        data.output.reasoning = { content = extra.reasoning_content } 
        -- so that codecompanion doesn't mistake this as a normal response with empty string as the content
        if data.output.content == "" then
          data.output.content = nil
        end
      end
      return data
    end
  }
}
```

Notes: 

1. You don't always have to set `data.output.content` to `nil`. This is mostly intended for `streaming`, and you may encounter issues in non-stream mode if you do that.
2. It's expected that the processed `data` table is returned at the end.

### `request.build_parameters`

For the purposes of the OpenAI adapter, no additional parameters need to be created. So we just pass this through:

```lua
handlers = {
  request = {
    build_parameters = function(self, params, messages)
      return params
    end,
  },
}
```

### `response.parse_inline`

From a design perspective, the inline strategy is very similar to the chat strategy. With the `parse_inline` handler we simply return the content we wish to be streamed into the buffer.

In the case of OpenAI, once we've checked the data we have back from the LLM and parsed it as JSON, we simply need to:

```lua
---Output the data from the API ready for inlining into the current buffer
---@param self CodeCompanion.HTTPAdapter
---@param data table The streamed JSON data from the API
---@param context table Useful context about the buffer to inline to
---@return string|table|nil
handlers = {
  response = {
    parse_inline = function(self, data, context)
      -- Data cleansed, parsed and validated
      -- ..
      local content = json.choices[1].delta.content
      if content then
        return content
      end
    end,
  },
}
```

The `parse_inline` handler also receives context from the buffer that initiated the request.

### `lifecycle.on_exit`

Handling errors from a streaming endpoint can be challenging. It's recommended that any errors are managed in the `on_exit` handler which is initiated when the response has completed. In the case of OpenAI, if there is an error, we'll see a response back from the API like:

```sh
data: {
data:     "error": {
data:         "message": "Incorrect API key provided: 1sk-F18b****************************************XdwS. You can find your API key at https://platform.openai.com/account/api-keys.",
data:         "type": "invalid_request_error",
data:         "param": null,
data:         "code": "invalid_api_key"
data:     }
data: }
```

This would be challenging to parse! Thankfully we can leverage the `on_exit` handler which receives the final payload, resembling:

```lua
{
  body = '{\n    "error": {\n        "message": "Incorrect API key provided: 1sk-F18b****************************************XdwS. You can find your API key at https://platform.openai.com/account/api-keys.",\n        "type": "invalid_request_error",\n        "param": null,\n        "code": "invalid_api_key"\n    }\n}',
  exit = 0,
  headers = { "date: Thu, 03 Oct 2024 08:05:32 GMT" },
  status = 401
}
```

and that's much easier to work with:

```lua
---Function to run when the request has completed. Useful to catch errors
---@param self CodeCompanion.HTTPAdapter
---@param data table
---@return nil
handlers = {
  lifecycle = {
    on_exit = function(self, data)
      if data.status >= 400 then
        log:error("Error: %s", data.body)
      end
    end,
  },
}
```

The `log:error` call ensures that any errors are logged to the logfile as well as displayed to the user in Neovim. It's also important to reference that the `parse_chat` and `parse_inline` handlers need to be able to ignore any errors from the API and let `on_exit` handle them.

### `lifecycle.setup` and `lifecycle.teardown`

The `setup` handler will execute before the request is sent to the LLM's endpoint and before the environment variables have been set. This is leveraged in the Copilot adapter to obtain the token before it's resolved as part of the environment variables table. The `setup` handler **must** return a boolean value so the `http.lua` file can determine whether to proceed with the request.

The `teardown` handler will execute once the request has completed and after `on_exit`.

Example:

```lua
handlers = {
  lifecycle = {
    setup = function(self)
      -- Perform initialization
      return true  -- Must return boolean
    end,

    teardown = function(self)
      -- Clean up resources
    end,
  },
}
```

### The Utility File

A lot of LLM endpoints claim to be "OpenAI Compatible" yet have odd quirks which prevent you from using the OpenAI Adapter. Common issues can be:

- System messages have to be the first message (`anthropic`, `deepseek`)
- System messages have to be one message (`anthropic`, `deepseek`)
- Messages must follow a `User -> LLM -> User -> LLM` turn based flow (`deepseek`)

To address this, an [adapter utilities](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/utils/adapters.lua) file has been created that you can leverage in building or extending your own adapters. Finally, always refer to the pre-built adapters as a reference point.

## Schema

The schema table describes the settings/parameters for the LLM. If the user has `display.chat.show_settings = true` then this table will be exposed at the top of the chat buffer.

We'll explore some of the options in the Copilot adapter's schema table:

```lua
schema = {
  model = {
    order = 1,
    mapping = "parameters",
    type = "enum",
    desc = "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
    ---@type string|fun(): string
    default = "gpt-4o-2024-08-06",
    choices = {
      ["o3-mini-2025-01-31"] = { opts = { can_reason = true } },
      ["o1-2024-12-17"] = { opts = { can_reason = true } },
      ["o1-mini-2024-09-12"] = { opts = { can_reason = true } },
      "claude-3.5-sonnet",
      "claude-3.7-sonnet",
      "claude-3.7-sonnet-thought",
      "gpt-4o-2024-08-06",
      "gemini-2.0-flash-001",
    },
  },
}
```

The model key sets out the specific model which is to be used to interact with the Copilot endpoint. We've listed the default, in this example, as `gpt-4o-2024-08-06` but we allow the user to choose from a possible five options, via the `choices` key. We've given this an order value of `1` so that it's always displayed at the top of the chat buffer. We've also given it a useful description as this is used in the virtual text when a user hovers over it. Finally, we've specified that it has a mapping property of `parameters`. This tells the adapter that we wish to map this model key to the parameters part of the HTTP request. You'll also notice that some of the models have a table attached to them. This can be useful if you need to do conditional logic in any of the handler methods at runtime.

Let's take a look at one more schema value:

```lua
temperature = {
  order = 2,
  mapping = "parameters",
  type = "number",
  default = 0,
  ---@param self CodeCompanion.HTTPAdapter
  condition = function(self)
    local model = self.schema.model.default
    if type(model) == "function" then
      model = model()
    end
    return not vim.startswith(model, "o1")
  end,
  -- This isn't in the Copilot adapter but it's useful to reference!
  validate = function(n)
    return n >= 0 and n <= 2, "Must be between 0 and 2"
  end,
  desc = "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
},
```

You'll see we've specified a function call for the `condition` key. We're simply checking that the model name doesn't start with `o1` as these models don't accept temperature as a parameter. You'll also see we've specified a function call for the `validate` key. We're simply checking that the value of the temperature is between 0 and 2.

For some endpoints, like OpenAI's [Responses API](https://platform.openai.com/docs/api-reference/responses/create?api-mode=responses), schema values may need to be nested in the parameters:

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

To accomplish this, you can use dot notation:

```lua
["reasoning.effort"] = {
  mapping = "parameters",
  type = "string",
  -- ...
},
```

## Function Calling / Tool Use

In order to enable your adapter to make use of [Function Calling](https://platform.openai.com/docs/guides/function-calling?api-mode=chat), you need to setup some additional handlers:

- `request.build_tools` - which transforms the tools provided by CodeCompanion into a schema supported by the adapter
- `tools.format_calls` - which [formats](https://platform.openai.com/docs/guides/function-calling?api-mode=chat#handling-function-calls) the adapters tool calls and puts them into the http request
- `tools.format_response` - which formats and outputs the adapter's tool call so it can be included in the chat buffer's messages stack

You will also need to ensure that `opts.tools = true` and the `parse_chat` handler has tools included as an optional final parameter like `parse_chat = function(self, data, tools)`. From experience, whilst many LLMs claim to support the OpenAI API standard for function calling, they can require some additional configuration to work as expected.

Example:

```lua
handlers = {
  request = {
    build_tools = function(self, tools)
      if not self.opts.tools or not tools then
        return
      end
      -- Transform tools into LLM's expected format
      return { tools = transformed_tools }
    end,
  },

  tools = {
    format_calls = function(self, tools)
      -- Format tool calls for the request
      return formatted_calls
    end,

    format_response = function(self, tool_call, output)
      -- Format tool response for LLM
      return {
        role = self.roles.tool or "tool",
        tools = {
          call_id = tool_call.id,
        },
        content = output,
        opts = { visible = false },
      }
    end,
  },
}
```

## Migrating from Old Handler Format

If you have an existing adapter using the old flat handler structure, it will continue to work without changes. However, to migrate to the new nested structure for better organization:

**Old format:**
```lua
handlers = {
  setup = function(self) end,
  form_parameters = function(self, params, messages) end,
  form_messages = function(self, messages) end,
  chat_output = function(self, data, tools) end,
  inline_output = function(self, data, context) end,
  on_exit = function(self, data) end,
  teardown = function(self) end,
  tools = {
    format_tool_calls = function(self, tools) end,
    output_response = function(self, tool_call, output) end,
  },
}
```

**New format:**
```lua
handlers = {
  lifecycle = {
    setup = function(self) end,
    on_exit = function(self, data) end,
    teardown = function(self) end,
  },
  request = {
    build_parameters = function(self, params, messages) end,
    build_messages = function(self, messages) end,
  },
  response = {
    parse_chat = function(self, data, tools) end,
    parse_inline = function(self, data, context) end,
  },
  tools = {
    format_calls = function(self, tools) end,
    format_response = function(self, tool_call, output) end,
  },
}
```
