# Adapters

In CodeCompanion, adapters are interfaces that act as a bridge between the plugin's functionality and a generative AI service. All adapters must follow the same strict implementation which is discussed below.

This guide is intended to serve as a reference for anyone who wishes to contribute an adapter to the plugin or understand the inner workings of existing adapters.

## The Adapter Interface

Let's take a look at the interface of an adapter as per the `adapter.lua` file:

```lua
---@class CodeCompanion.Adapter
---@field name string The name of the adapter
---@field roles table The mapping of roles in the config to the LLM's defined roles
---@field url string The URL of the generative AI service to connect to
---@field env? table Environment variables which can be referenced in the parameters
---@field env_replaced? table Replacement of environment variables with their actual values
---@field headers table The headers to pass to the request
---@field parameters table The parameters to pass to the request
---@field raw? table Any additional curl arguments to pass to the request
---@field opts? table Additional options for the adapter
---@field callbacks table Functions which link the output from the request to CodeCompanion
---@field callbacks.form_parameters fun()
---@field callbacks.form_messages fun()
---@field callbacks.is_complete fun()
---@field callbacks.chat_output fun()
---@field callbacks.on_stdout fun()
---@field callbacks.inline_output fun()
---@field schema table Set of parameters for the generative AI service that the user can customise in the chat buffer
```

Everything up to the callbacks should be self-explanatory. We're simply providing details of the generative AI's API to the curl library and executing the request. The real intelligence of the adapter comes from the callbacks table which is a set of functions which bridge the functionality of the plugin to the generative AI service.

## Environment Variables

When building an adapter, you'll need to inject variables into different parts of the adapter class. If we take the [Google Gemini](https://github.com/google-gemini/cookbook/blob/main/quickstarts/rest/Streaming_REST.ipynb) endpoint as an example, we need to inject the model and API key variables into the URL of `https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?alt=sse&key=${api_key}`. Whereas with [OpenAI](https://platform.openai.com/docs/api-reference/authentication), we need an `Authorization` http header to contain our API key.

Let's take a look at the `env` table from the Google Gemini adapter that comes with the plugin:

```lua
env = {
  api_key = "GEMINI_API_KEY",
  model = "schema.model.default",
},
```

The key `api_key` represents the name of the variable which can be injected in the adapter, and the value can represent one of:

- A command to execute on the user's system
- An environment variable from the user's system
- A function to be executed at runtime
- A path to an item in the adapter's schema table

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

## Callbacks aka The Bridge

Currently, the callbacks table requires 5 functions to be implemented:

- `form_parameters` - A function which can be used to set the parameters of the request
- `form_messages` - _Most_ generative AI services have a `messages` array in the body of the request which contains the conversation. This function can be used to format and structure that array
- `chat_output` - A function to format the output of the request into a Lua table that plugin can parse for the chat buffer
- `inline_output` - A function to format the output of the request into a Lua table that plugin can parse, inline, to the current buffer

### An Example: The OpenAI Adapter

> [!TIP]
> All of the adapters in the plugin come with their own tests. These serve as a great reference to understand how they're working with the output of the API

Let's take a look at a real world example of how we've implemented the OpenAI adapter.

**API Output**

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

**Chat Buffer Output**

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

**`form_messages`**

The chat buffer's output is passed to the callback in for the form of the `messages` parameter. So we can just output this as part of a messages table:

```lua
callbacks = {
  form_messages = function(self, messages)
    return { messages = messages }
  end,
}
```

**`chat_output`**

Now let's look at how we format the output from OpenAI. Running that request results in:

```sh
data: {"id":"chatcmpl-90DdmqMKOKpqFemxX0OhTVdH042gu","object":"chat.completion.chunk","created":1709839462,"model":"gpt-4-0125-preview","system_fingerprint":"fp_70b2088885","choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}]}
```

```sh
data: {"id":"chatcmpl-90DdmqMKOKpqFemxX0OhTVdH042gu","object":"chat.completion.chunk","created":1709839462,"model":"gpt-4-0125-preview","system_fingerprint":"fp_70b2088885","choices":[{"index":0,"delta":{"content":"Programming"},"logprobs":null,"finish_reason":null}]}
```

```sh
data: {"id":"chatcmpl-90DdmqMKOKpqFemxX0OhTVdH042gu","object":"chat.completion.chunk","created":1709839462,"model":"gpt-4-0125-preview","system_fingerprint":"fp_70b2088885","choices":[{"index":0,"delta":{"content":" language"},"logprobs":null,"finish_reason":null}]},
```

```sh
data: [DONE]
```

> [!IMPORTANT]
> Note that the `chat_output` callback requires a table containing `status` and `output` to be returned.

Remember that we're streaming from the API so the request comes through in batches. Thankfully the client implementation handles this and we just have to handle formatting the output into the chat buffer.

The first thing to note with streaming endpoints is that they don't return valid JSON. In this case, the output is prefixed with `data: `. So let's remove it:

```lua
callbacks = {
  chat_output = function(data)
    data = data:sub(7)
  end
}
```

> [!IMPORTANT]
> The data passed to the `chat_output` callback is the response from OpenAI

We can then decode the JSON using native vim functions:

```lua
callbacks = {
  chat_output = function(data)
    data = data:sub(7)

    local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

    if not ok then
      return {
        status = "error",
        output = string.format("Error malformed json: %s", json),
      }
    end
  end
}
```

We want to include any nil values so we pass in `luanil = { object = true }`.

Examining the output of the API, we see that the streamed data is stored in a `choices[1].delta` table. That's easy to pickup:

```lua
callbacks = {
  chat_output = function(data)
    ---
    local delta = json.choices[1].delta
  end
}
```

and we can then access the new streamed data that we want to write into the chat buffer, with:

```lua
callbacks = {
  chat_output = function(data)
    local output = {}
    ---
    local delta = json.choices[1].delta

    if delta.content then
      output.content = delta.content
      output.role = delta.role or nil
    end
  end
}
```

And then we can return the output:

```lua
callbacks = {
  chat_output = function(data)
    --
    return {
      status = "success",
      output = output,
    }
  end
}
```

Now if we put it all together, and put some checks in place to make sure that we have data in our response:

```lua
callbacks = {
  chat_output = function(data)
    local output = {}

    if data and data ~= "" then
      data = data:sub(7)
      local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

      if not ok then
        return {
          status = "error",
          output = string.format("Error malformed json: %s", json),
        }
      end

      local delta = json.choices[1].delta

      if delta.content then
        output.content = delta.content
        output.role = delta.role or nil
      end

      -- log:trace("----- For Adapter test creation -----\nOutput: %s\n ---------- // END ----------", output)

      return {
        status = "success",
        output = output,
      }
    end

    return nil
  end
},
```

**`form_parameters`**

For the purposes of the OpenAI adapter, no additional parameters need to be created. So we just pass this through:

```lua
callbacks = {
  form_parameters = function(params, messages)
    return params
  end,
}
```

**`inline_output`**

From a design perspective, the inline strategy is very similar to the chat strategy. With the `inline_output` callback we simply return the content we wish to be streamed into the buffer.

In the case of OpenAI, once we've checked the data we have back from the LLM and parsed it as JSON, we simply need to:

```lua
---Output the data from the API ready for inlining into the current buffer
---@param data table The streamed JSON data from the API, also formatted by the format_data callback
---@param context table Useful context about the buffer to inline to
---@return string|table|nil
inline_output = function(data, context)
  -- Data cleansed, parsed and validated
  -- ..
  local content = json.choices[1].delta.content
  if content then
    return content
  end
end,
```

The `inline_output` callback also receives context from the buffer that initiated the request.

**`on_stdout`**

Handling errors from a streaming endpoint can be challenging. It's recommended that any errors are managed in the `on_stdout` callback which is initiated when the response has completed. In the case of OpenAI, if there is an error, we'll see a response like:

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

This is challenging to parse as each line represents a chunk from the API. Instead, it's much easier to wait for the request to complete before trying to determine if an error occured. We can do this by leveraging the `on_stdout` callback:

```lua
---Callback to catch any errors from the standard output
---@param data table
---@return nil
on_stdout = function(data)
  local stdout = table.concat(data._stdout_results)

  local ok, json = pcall(vim.json.decode, stdout, { luanil = { object = true } })
  if ok then
    log:trace("stdout: %s", json)
    if json.error then
      log:error("Error: %s", json.error.message)
    end
  end
end,
```

The `log:error` call ensures that any errors are logged to the logfile as well as displayed to the user in Neovim. It's also important to reference that the `chat_output` and `inline_output` callbacks need to be able to ignore any errors from the API and let the `on_stdout` handle them.

## Schema

The schema table describes the settings/parameters for the Generative AI service. If the user has `display.chat.show_settings = true` then this table will be exposed at the top of the chat buffer.

We'll explore some of the options in the OpenAI adapter's schema table:

```lua
schema = {
  model = {
    order = 1,
    mapping = "parameters",
    type = "enum",
    desc = "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
    default = "gpt-4o",
    choices = {
      "gpt-4o",
      "gpt-4o-mini",
      "gpt-4-turbo-preview",
      "gpt-4",
      "gpt-3.5-turbo",
    },
  },
}
```

The model key sets out the specific model which is to be used to interact with the OpenAI endpoint. We've listed the default, in this example, as `gpt-4o` but we allow the user to choose from a possible five options, via the `choices` key. We've given this an order value of `1` so that it's always displayed at the top of the chat buffer. We've also given it a useful description as this is used in the virtual text when a user hovers over it. Finally, we've specified that it has a mapping property of `parameters`. This tells the adapter that we wish to map this model key to the parameters part of the HTTP request.

Let's take a look at one more:

```lua
temperature = {
  order = 2,
  mapping = "parameters",
  type = "number",
  optional = true,
  default = 1,
  desc = "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
  validate = function(n)
    return n >= 0 and n <= 2, "Must be between 0 and 2"
  end,
},
```

You'll see we've specified a function call for the `validate` key. We're simply checking that the value of the temperature is between 0 and 2. Again, we'll use virtual text and LSP warnings to alert the user if they've strayed from these constraints.

## Summary

This guide provided an overview for how the plugin uses adapters to connect to a variety of different Generative AI services.
