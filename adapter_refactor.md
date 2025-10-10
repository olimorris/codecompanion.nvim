## olimorris

> Context:
> - <memory>CLAUDE.md</memory>
> - <memory>.codecompanion/adapters/adapters.md</memory>
> - <file>lua/codecompanion/adapters/init.lua</file>
> - <file>lua/codecompanion/adapters/shared.lua</file>
> - <file>lua/codecompanion/adapters/http/init.lua</file>
> - <file>lua/codecompanion/adapters/http/openai.lua</file>
> - <file>lua/codecompanion/http.lua</file>
> - <file>.codecompanion/adapters/plenary_curl.md</file>

How would you improve the structure of http adapters? Notably their handlers?

## CodeCompanion (Anthropic)

### Reasoning

The user is asking about how to improve the structure of HTTP adapters, particularly their handlers. Let me analyze the current structure:

Current structure:
1. HTTP adapters have a `handlers` table with various functions like:
   - setup
   - set_body
   - form_parameters
   - form_messages
   - form_reasoning
   - form_tools
   - tokens
   - chat_output
   - inline_output
   - tools.format_tool_calls
   - tools.output_response
   - on_exit
   - teardown

2. These handlers are called at various points in the HTTP client lifecycle

Issues I can see:
1. **Inconsistent naming**: Some handlers use verbs (setup, teardown), others use nouns (tokens), others use form_ prefix
2. **Unclear responsibilities**: Some handlers transform data, others handle lifecycle events, others are callbacks
3. **Nested handlers**: The `tools` namespace is nested but other related functionality isn't
4. **Optional vs required**: It's not clear which handlers are required vs optional
5. **Return values**: Different handlers return different things (nil, table, boolean) without clear conventions
6. **Side effects**: Some handlers modify the adapter in place, others return new data
7. **Testing**: The flat structure makes it harder to mock/test individual handler groups

Improvements I would suggest:

1. **Categorize handlers by lifecycle phase**:
   - Lifecycle hooks: setup, teardown, on_exit
   - Request builders: build_parameters, build_messages, build_tools
   - Response parsers: parse_response, parse_tokens, parse_tools
   - Formatters: format_for_chat, format_for_inline

2. **Consistent naming conventions**:
   - Lifecycle: on_setup, on_exit, on_teardown
   - Builders: build_* (build_parameters, build_messages, build_tools)
   - Parsers: parse_* (parse_chat_output, parse_inline_output, parse_tokens)
   - Formatters: format_* (format_tool_calls, format_tool_response)

3. **Group related handlers**:
   - request: { build_parameters, build_messages, build_tools, build_body }
   - response: { parse_chat, parse_inline, parse_tokens }
   - tools: { build_tools, parse_tool_calls, format_tool_calls, format_tool_response }
   - lifecycle: { setup, teardown, on_exit }

4. **Clear contracts**:
   - Document input/output types for each handler
   - Use proper type annotations
   - Make required vs optional clear

I'll continue exploring strategies to enhance the adapter's modularity and flexibility, focusing on creating a more robust and predictable handler structure.

Distinct function categories will help manage complexity:
   - Pure transformation functions that process data cleanly
   - State-modifying functions with explicit side effects
   - Reactive event handlers managing system lifecycle transitions

### Response

Based on analyzing the current adapter structure, here are key improvements I'd recommend:

## Current Issues

1. **Inconsistent naming**: `setup`, `form_parameters`, `chat_output`, `tokens` - no clear pattern
2. **Mixed responsibilities**: Lifecycle hooks, data transformation, and formatting all in one flat namespace
3. **Unclear contracts**: Different return types (nil, table, boolean) without clear conventions
4. **Nested inconsistency**: `tools.*` is nested but related functionality isn't
5. **Testing complexity**: Flat structure makes mocking/testing difficult

## Proposed Structure

### 1. Group by Lifecycle Phase

````lua
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
````

### 2. Benefits

**Clearer responsibilities**:
- `lifecycle.*` = side effects, state changes
- `request.*` = build outgoing data
- `response.*` = parse incoming data
- `tools.*` = tool-specific transforms

**Better discoverability**:
````lua
-- Old: What does this do?
handlers.form_parameters()
handlers.chat_output()

-- New: Clear intent
handlers.request.build_parameters()
handlers.response.parse_chat()
````

**Easier testing**:
````lua
-- Mock just the response parsers
local mock_handlers = {
  response = {
    parse_chat = function() return test_data end
  }
}
````

**Migration path** (backwards compatible):
````lua
-- In http/init.lua, add shims:
handlers.form_parameters = handlers.request.build_parameters
handlers.chat_output = handlers.response.parse_chat
-- ...etc
````

### 3. Example Refactored Adapter

````lua
-- lua/codecompanion/adapters/http/openai.lua
return {
  name = "openai",
  -- ...other config...

  handlers = {
    lifecycle = {
      setup = function(self)
        -- Configure vision, streaming, etc
        return true
      end,
    },

    request = {
      build_parameters = function(self, params, messages)
        return params
      end,

      build_messages = function(self, messages)
        return { messages = self:_transform_messages(messages) }
      end,

      build_tools = function(self, tools)
        if not self.opts.tools or vim.tbl_count(tools) == 0 then
          return nil
        end
        return { tools = self:_transform_tools(tools) }
      end,
    },

    response = {
      parse_chat = function(self, data, tools)
        -- Parse streaming/non-streaming chat response
      end,

      parse_tokens = function(self, data)
        -- Extract token count
      end,
    },

    tools = {
      format_calls = function(self, tools)
        return tools -- Already in OpenAI format
      end,

      format_response = function(self, tool_call, output)
        return {
          role = "tool",
          tool_call_id = tool_call.id,
          content = output,
        }
      end,
    },
  },
}
````

**Next step**: Would you like me to create a migration PR that refactors one adapter as a proof-of-concept while maintaining backwards compatibility?

## olimorris

> Context:
> - <memory>CLAUDE.md</memory>
> - <memory>.codecompanion/adapters/adapters.md</memory>
> - <file>lua/codecompanion/adapters/init.lua</file>
> - <file>lua/codecompanion/adapters/shared.lua</file>
> - <file>lua/codecompanion/adapters/http/init.lua</file>
> - <file>lua/codecompanion/adapters/http/openai.lua</file>
> - <file>lua/codecompanion/http.lua</file>
> - <file>.codecompanion/adapters/plenary_curl.md</file>
> - <file>lua/codecompanion/adapters/http/anthropic.lua</file>

This is very sensible. Of course, full, backwards compatibility is essential.

Do you think there's a clean way we could do this? E.g. have one masterfile that contains mappings between the old names and the new?

Sharing the anthropic adapter too because that has `form_reasoning` which is arguably a response method.

## CodeCompanion (Anthropic)

### Reasoning

The user wants to refactor the adapter handler structure but maintain full backwards compatibility. They're asking for a clean way to map old names to new names, preferably in a central location.

Looking at the anthropic adapter, I can see:
- `form_reasoning` which returns parsed reasoning data - this is indeed a response parser
- All the other handlers similar to OpenAI

The key challenge is:
1. Provide the new grouped structure
2. Allow old code to still use `handlers.form_parameters()` etc
3. Have a central mapping file for the shim

Let me think about the cleanest approach:

Option 1: Proxy/metatable approach
- Each adapter has the new structure
- A metatable on `handlers` provides backwards compat lookups
- A central config file defines the mappings

Option 2: Shim layer in http/init.lua
- When resolving an adapter, apply shims automatically
- Central mapping table

Option 3: Migration helper module
- A separate module that adds backwards compat
- Applied when adapter is resolved

I think Option 1 with a metatable is cleanest because:
- Mappings are centralized
- No code duplication
- Transparent to users
- Easy to deprecate later (add warnings)

Let me design this:

1. Create `lua/codecompanion/adapters/http/handler_compat.lua` with mapping
2. Apply metatable in http/init.lua when resolving
3. Adapters use new structure
4. Old code still works

This would look something like:

```lua
-- handler_compat.lua
return {
  mappings = {
    setup = "lifecycle.setup",
    form_parameters = "request.build_parameters",
    form_messages = "request.build_messages",
    form_tools = "request.build_tools",
    form_reasoning = "response.parse_reasoning",
    set_body = "request.build_body",


```

I see we need comprehensive compatibility support that handles multiple scenarios. The mapping approach allows seamless transition between old and new adapter structures. We'll need a flexible mechanism that can:
1. Handle existing flat adapter implementations
2. Support new grouped structural approaches
3. Provide smooth migration path
4. Minimize breaking changes for current users

The metatable strategy offers an elegant solution by creating a transparent translation layer. This approach ensures existing code continues functioning while enabling future architectural improvements.

By defining a central mapping configuration, we can dynamically redirect handler references without disrupting current implementations. The key is creating intelligent shims that intelligently route method calls across different structural paradigms.

### Response

Yes! A central mapping file with metatables is the cleanest approach. Here's how I'd structure it:

## Proposal: Central Compatibility Layer

### 1. Create Handler Compatibility Module

````lua
-- lua/codecompanion/adapters/http/handler_compat.lua

local M = {}

---Maps old handler names to new grouped paths
---@type table<string, string>
M.mappings = {
  -- Lifecycle
  setup = "lifecycle.setup",
  on_exit = "lifecycle.on_exit",
  teardown = "lifecycle.teardown",

  -- Request builders
  form_parameters = "request.build_parameters",
  form_messages = "request.build_messages",
  form_tools = "request.build_tools",
  set_body = "request.build_body",

  -- Response parsers
  chat_output = "response.parse_chat",
  inline_output = "response.parse_inline",
  form_reasoning = "response.parse_reasoning",
  tokens = "response.parse_tokens",
}

---Reverse mappings for detecting new-style structure
---@type table<string, string>
M.reverse_mappings = {}
for old, new in pairs(M.mappings) do
  M.reverse_mappings[new] = old
end

---Navigate a dot-separated path in a table
---@param tbl table
---@param path string e.g., "lifecycle.setup"
---@return any|nil
local function get_nested(tbl, path)
  local current = tbl
  for segment in path:gmatch("[^.]+") do
    if not current[segment] then
      return nil
    end
    current = current[segment]
  end
  return current
end

---Set a value at a dot-separated path
---@param tbl table
---@param path string
---@param value any
local function set_nested(tbl, path, value)
  local segments = {}
  for segment in path:gmatch("[^.]+") do
    table.insert(segments, segment)
  end

  local current = tbl
  for i = 1, #segments - 1 do
    if not current[segments[i]] then
      current[segments[i]] = {}
    end
    current = current[segments[i]]
  end
  current[segments[#segments]] = value
end

---Apply bidirectional compatibility shims to handlers
---@param handlers table
---@return table handlers with shims applied
function M.apply_shims(handlers)
  if not handlers then
    return handlers
  end

  -- Detect which structure we're dealing with
  local has_grouped = handlers.lifecycle or handlers.request or handlers.response
  local has_flat = not not (
    handlers.setup or
    handlers.form_parameters or
    handlers.chat_output
  )

  if has_grouped then
    -- New structure: add old-name shims
    for old_name, new_path in pairs(M.mappings) do
      if not handlers[old_name] then
        local fn = get_nested(handlers, new_path)
        if fn then
          handlers[old_name] = fn
        end
      end
    end
  elseif has_flat then
    -- Old structure: create groups and add references
    for old_name, new_path in pairs(M.mappings) do
      if handlers[old_name] then
        -- Set the function at the new path
        set_nested(handlers, new_path, handlers[old_name])
      end
    end
  end

  -- Add metatable for dynamic access (catch any we missed)
  return setmetatable(handlers, {
    __index = function(t, key)
      -- Try old -> new mapping
      local new_path = M.mappings[key]
      if new_path then
        return get_nested(t, new_path)
      end
      return nil
    end
  })
end

---Add deprecation warnings (for future use)
---@param handlers table
---@param log table Logger instance
---@return table handlers with warnings
function M.add_deprecation_warnings(handlers, log)
  local warned = {}

  return setmetatable(handlers, {
    __index = function(t, key)
      if M.mappings[key] and not warned[key] then
        log:warn(
          "Handler '%s' is deprecated. Use '%s' instead.",
          key,
          M.mappings[key]
        )
        warned[key] = true
      end

      local new_path = M.mappings[key]
      if new_path then
        return get_nested(t, new_path)
      end
      return rawget(t, key)
    end
  })
end

return M
````

### 2. Apply in Adapter Resolution

````lua
-- lua/codecompanion/adapters/http/init.lua (modifications)

local compat = require("codecompanion.adapters.http.handler_compat")

function Adapter.resolve(adapter, opts)
  -- ... existing resolution code ...

  -- Apply compatibility shims to handlers
  if adapter.handlers then
    adapter.handlers = compat.apply_shims(adapter.handlers)
  end

  return Adapter.set_model(adapter)
end
````

### 3. Update Adapters Incrementally

New adapters use grouped structure:

````lua
-- lua/codecompanion/adapters/http/anthropic.lua (refactored)

return {
  name = "anthropic",
  -- ... config ...

  handlers = {
    lifecycle = {
      setup = function(self)
        -- existing setup logic
      end,

      on_exit = function(self, data)
        -- existing on_exit logic
      end,
    },

    request = {
      build_parameters = function(self, params, messages)
        -- existing form_parameters logic
      end,

      build_messages = function(self, messages)
        -- existing form_messages logic
      end,

      build_tools = function(self, tools)
        -- existing form_tools logic
      end,
    },

    response = {
      parse_chat = function(self, data, tools)
        -- existing chat_output logic
      end,

      parse_inline = function(self, data, context)
        -- existing inline_output logic
      end,

      parse_reasoning = function(self, data)
        -- existing form_reasoning logic
      end,

      parse_tokens = function(self, data)
        -- existing tokens logic
      end,
    },

    tools = {
      format_calls = function(self, tools)
        -- existing format_tool_calls logic
      end,

      format_response = function(self, tool_call, output)
        -- existing output_response logic
      end,
    },
  },
}
````

### 4. Benefits of This Approach

**Transparent compatibility**:
````lua
-- Old code still works
local output = adapter.handlers.chat_output(adapter, data, tools)

-- New code also works
local output = adapter.handlers.response.parse_chat(adapter, data, tools)

-- Both access the same function!
````

**Works with old adapters**:
````lua
-- Old flat structure adapter
handlers = {
  setup = function() end,
  chat_output = function() end,
}

-- After apply_shims(), can access as:
handlers.setup()  -- works
handlers.lifecycle.setup()  -- also works!
````

**Easy deprecation path**:
````lua
-- In v18.0.0, switch to warnings:
adapter.handlers = compat.add_deprecation_warnings(
  adapter.handlers,
  require("codecompanion.utils.log")
)

-- In v19.0.0, remove old names entirely
-- (just stop calling apply_shims)
````

**Minimal performance impact**:
- Shims are applied once at resolve time
- Metatable only used as fallback
- No runtime overhead after initial setup

### 5. Migration Path

1. **v17.x**: Add compat layer, start refactoring adapters
2. **v17.5**: All core adapters use new structure (old names still work)
3. **v18.0**: Enable deprecation warnings
4. **v19.0**: Remove old name support

Would you like me to create a PR with:
1. The `handler_compat.lua` module
2. Refactored `anthropic.lua` adapter as proof-of-concept
3. Tests demonstrating bidirectional compatibility

**Next step**: Shall I also add helper methods to `handler_compat.lua` for common handler access patterns (e.g., safe calling with error handling)?

## olimorris

> Context:
> - <memory>CLAUDE.md</memory>
> - <memory>.codecompanion/adapters/adapters.md</memory>
> - <file>lua/codecompanion/adapters/init.lua</file>
> - <file>lua/codecompanion/adapters/shared.lua</file>
> - <file>lua/codecompanion/adapters/http/init.lua</file>
> - <file>lua/codecompanion/adapters/http/openai.lua</file>
> - <file>lua/codecompanion/http.lua</file>
> - <file>.codecompanion/adapters/plenary_curl.md</file>
> - <file>lua/codecompanion/adapters/http/anthropic.lua</file>


