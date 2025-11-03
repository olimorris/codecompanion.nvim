# Adapters

In CodeCompanion, adapters are used to connect to LLMs or Agents. HTTP adapters contain various options for the LLM's endpoint alongside a defined schema for properties such as the model, temperature, top k, top p etc. HTTP adapters also contain various handler functions which define how messages which are sent to the LLM should be formatted alongside how output from the LLM should be received and displayed in the chat buffer. The adapters are defined in the `lua/codecompanion/adapters` directory.

## Handler Structure

Adapters use a nested handler structure that organizes functions by their purpose:

```lua
handlers = {
  -- Lifecycle hooks (side effects)
  lifecycle = {
    ---Called when adapter is resolved
    ---@param self CodeCompanion.HTTPAdapter
    ---@return boolean success
    setup = function(self) end,

    ---Called after request completes
    ---@param self CodeCompanion.HTTPAdapter
    ---@param data table
    ---@return nil
    on_exit = function(self, data) end,

    ---Called during adapter cleanup
    ---@param self CodeCompanion.HTTPAdapter
    ---@return nil
    teardown = function(self) end,
  },

  -- Request builders (pure transforms)
  request = {
    ---Build request parameters
    ---@param self CodeCompanion.HTTPAdapter
    ---@param params table
    ---@param messages table
    ---@return table
    build_parameters = function(self, params, messages) end,

    ---Build message format for LLM
    ---@param self CodeCompanion.HTTPAdapter
    ---@param messages table
    ---@return table
    build_messages = function(self, messages) end,

    ---Build tools schema
    ---@param self CodeCompanion.HTTPAdapter
    ---@param tools table
    ---@return table|nil
    build_tools = function(self, tools) end,

    ---Build reasoning parameters (for models that support it)
    ---@param self CodeCompanion.HTTPAdapter
    ---@param messages table
    ---@return nil|{ content: string, _data: table }
    build_reasoning = function(self, messages) end,

    ---Set additional body parameters
    ---@param self CodeCompanion.HTTPAdapter
    ---@param data table
    ---@return table|nil
    build_body = function(self, data) end,
  },

  -- Response parsers (pure transforms)
  response = {
    ---Parse chat response
    ---@param self CodeCompanion.HTTPAdapter
    ---@param data string|table
    ---@param tools? table
    ---@return { status: string, output: table }|nil
    parse_chat = function(self, data, tools) end,

    ---Parse inline response
    ---@param self CodeCompanion.HTTPAdapter
    ---@param data string|table
    ---@param context? table
    ---@return { status: string, output: string }|nil
    parse_inline = function(self, data, context) end,

    ---Extract token count
    ---@param self CodeCompanion.HTTPAdapter
    ---@param data table
    ---@return number|nil
    parse_tokens = function(self, data) end,
  },

  -- Tool handlers (grouped functionality)
  tools = {
    ---Format tool calls for inclusion in request
    ---@param self CodeCompanion.HTTPAdapter
    ---@param tools table
    ---@return table
    format_calls = function(self, tools) end,

    ---Format tool response for LLM
    ---@param self CodeCompanion.HTTPAdapter
    ---@param tool_call table
    ---@param output string
    ---@return table
    format_response = function(self, tool_call, output) end,
  },
}
```

This structure provides clear separation of concerns:
- **lifecycle**: Side effects and initialization (setup, teardown, cleanup)
- **request**: Pure transformations for building requests (parameters, messages, tools)
- **response**: Pure transformations for parsing responses (chat, inline, tokens)
- **tools**: Tool-specific operations (formatting calls and responses)

### Calling Handlers

Throughout CodeCompanion, handlers are called using the `adapters.call_handler()` function, which provides backwards compatibility:

```lua
local adapters = require("codecompanion.adapters")

-- Call a handler
local result = adapters.call_handler(adapter, "parse_chat", data, tools)
local tokens = adapters.call_handler(adapter, "parse_tokens", data)

-- Handler automatically receives adapter as first argument
local setup_ok = adapters.call_handler(adapter, "setup")
```

## Backwards Compatibility

For backwards compatibility, CodeCompanion continues to support the old flat handler structure:

```lua
-- Old format (still supported)
handlers = {
  setup = function(self) end,
  form_parameters = function(self, params, messages) end,
  form_messages = function(self, messages) end,
  chat_output = function(self, data, tools) end,
  tools = {
    format_tool_calls = function(self, tools) end,
    output_response = function(self, tool_call, output) end,
  }
}
```

When calling handlers with the new names (e.g., `build_messages`), they automatically map to old names (e.g., `form_messages`) if the adapter uses the old format. The format is detected by checking for the presence of `lifecycle`, `request`, or `response` categories.

**Note**: The `tools` namespace has always existed in both old and new formats, so it cannot be used alone to detect the new format.

## Relevant Files

### adapters/init.lua

@./lua/codecompanion/adapters/init.lua

Currently CodeCompanion supports http and ACP adapters. This file provides the factory methods for resolving adapters and includes `call_handler()` for backwards-compatible handler invocation.

### adapters/shared.lua

@./lua/codecompanion/adapters/shared.lua

There are some functions that are shared between the two adapter types and these are contained in this file.

### adapters/http/init.lua

@./lua/codecompanion/adapters/http/init.lua

This is the logic for the HTTP adapters. Various logic sits within this file which allows the adapter to be resolved into a CodeCompanion.HTTPAdapter object before it's used throughout the plugin to connect to an LLM endpoint.

### Example Adapter: openai.lua

@./lua/codecompanion/adapters/http/openai.lua

Sharing an example HTTP adapter for OpenAI. Note: This adapter currently uses the old flat format but will be migrated to the new nested format in a future update.

## HTTP Client

@./lua/codecompanion/http.lua
@.codecompanion/adapters/plenary_curl.md

The http.lua module implements a provider-agnostic HTTP client for CodeCompanion that centralizes request construction, streaming, scheduling, and testability. It uses `adapters.call_handler()` to invoke adapter handlers in a backwards-compatible way, working seamlessly with both old and new handler formats.
