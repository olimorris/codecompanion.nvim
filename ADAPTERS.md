# Adapters

In CodeCompanion, adapters are an interface which act as a bridge between the plugin's functionality and a generative AI service. All adapters must follow the same strict implementation.

## The Adapter Interface

Let's take a look at the interface of an adapter as per the `adapter.lua` file:

```lua
---@class CodeCompanion.Adapter
---@field name string The name of the adapter
---@field url string The URL of the generative AI service to connect to
---@field env? table Environment variables which can be referenced in the parameters
---@field headers table The headers to pass to the request
---@field parameters table The parameters to pass to the request
---@field raw? table Any additional curl arguments to pass to the request
---@field opts? table Additional options for the adapter
---@field callbacks table Functions which link the output from the request to CodeCompanion
---@field callbacks.form_parameters fun()
---@field callbacks.form_messages fun()
---@field callbacks.is_complete fun()
---@field callbacks.chat_output fun()
---@field callbacks.inline_output fun()
---@field schema table Set of parameters for the generative AI service that the user can customise in the chat buffer
```

Everything up to the callbacks should be self-explanatory. We're simply providing details of the generative AI's API to the curl library and executing the request.

The real intelligence of the adapter comes from the callbacks table. This is a set of functions which bridge the functionality of the plugin to the generative AI service.

## Callbacks aka The Bridge

Currently, the callbacks table requires 5 functions to be implemented:

- `form_parameters` - A function which can be used to set the parameters of the request
- `form_messages` - _Most_ generative AI services have a `messages` array in the body of the request which contains the conversation. This function can be used to format and structure that array
- `is_complete` - A function to determine if the request has completed.
- `chat_output` - A function to format the output of the request into a Lua table that plugin can parse for the chat buffer
- `inline_output` - A function to format the output of the request into a Lua table that plugin can parse, inline, to the current buffer

### An Example: The OpenAI Adapter

> [!TIP]
> All of the adapters in the plugin come with their own tests. These serve as a great reference to understand how they're working with the output of the API

Let's take a look at a real world example of how we've implemented the OpenAI adapter.

#### API Output

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

#### Chat Buffer Output

The chat buffer, which is structured like:

```markdown
# user

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

#### `form_messages` callback

So we can just pass this to a messages table in the `form_messages` callback:

```lua
callbacks = {
  form_messages = function(messages)
    return { messages = messages }
  end,
}
```

#### `chat_output` callback

Now let's look at how we format the output from OpenAI. Running that request results in:

```json
data: {"id":"chatcmpl-90DdmqMKOKpqFemxX0OhTVdH042gu","object":"chat.completion.chunk","created":1709839462,"model":"gpt-4-0125-preview","system_fingerprint":"fp_70b2088885","choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}]}
```

```json
data: {"id":"chatcmpl-90DdmqMKOKpqFemxX0OhTVdH042gu","object":"chat.completion.chunk","created":1709839462,"model":"gpt-4-0125-preview","system_fingerprint":"fp_70b2088885","choices":[{"index":0,"delta":{"content":"Programming"},"logprobs":null,"finish_reason":null}]}
```

```json
data: {"id":"chatcmpl-90DdmqMKOKpqFemxX0OhTVdH042gu","object":"chat.completion.chunk","created":1709839462,"model":"gpt-4-0125-preview","system_fingerprint":"fp_70b2088885","choices":[{"index":0,"delta":{"content":" language"},"logprobs":null,"finish_reason":null}]},
```

```json
data: [DONE]
```

> [!IMPORTANT]
> Note that the `chat_output` callback requires a table containing `status` and `output` to be returned.

Remember that we're streaming from the API so the request comes through in batches. Thankfully the client implementation handles this and we just have to handle formatting the output into the chat buffer.

The first thing to note with streaming endpoints is that they often contain text like `data: ` that we don't need. So let's remove it:

```lua
callbacks = {
  chat_output = function(data)
    data = data:sub(7)
  end
}
```

> [!IMPORTANT]
> The data passed to the `chat_output` callback is the data from OpenAI

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

Examining the output of the API, we see that the streamed data is housed in a choices then delta array. That's easy to pickup:

```lua
callbacks = {
  chat_output = function(data)
    ---
    local delta = json.choices[1].delta
  end
}
```

and we can pickup the new streamed data with:

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

Now if we put it all together, and put some checks in place that data is returned from OpenAI:

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

#### `is_complete` callback

Now we can check that the request has finalised by determining if the API returns `[DONE]`. We can do that with:

```lua
callbacks = {
  is_complete = function(data)
    if data then
      data = data:sub(7)
      return data == "[DONE]"
    end
    return false
  end,
}
```

This will tell the client to end the connection with the OpenAI endpoint.

#### `form_parameters` callback

For the purposes of the OpenAI adapter, no additional parameters need to be created. So we just pass this through:

```lua
callbacks = {
  form_parameters = function(params, messages)
    return params
  end,
}
```

#### `inline_output` callback

[To be updated]

## Schema

[To be updated]

## Creating Your Own Adapter
