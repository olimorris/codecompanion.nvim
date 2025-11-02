local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local shared = require("codecompanion.adapters.shared")

---Check if adapter uses the new handler format
---@param adapter CodeCompanion.HTTPAdapter
---@return boolean
local function uses_new_handlers(adapter)
  if not adapter.handlers then
    return false
  end
  return adapter.handlers.lifecycle ~= nil or adapter.handlers.request ~= nil or adapter.handlers.response ~= nil
end

---Get handler function with backwards compatibility
---@param adapter CodeCompanion.HTTPAdapter
---@param name string Handler name
---@return function|nil
local function get_handler(adapter, name)
  if not adapter.handlers then
    return nil
  end

  -- New nested format - search all categories
  if uses_new_handlers(adapter) then
    local categories = { "lifecycle", "request", "response", "tools" }
    for _, category in ipairs(categories) do
      if adapter.handlers[category] and adapter.handlers[category][name] then
        return adapter.handlers[category][name]
      end
    end
    return nil
  end

  -- Old flat format - map to old names
  local old_names = {
    -- lifecycle
    setup = "setup",
    on_exit = "on_exit",
    teardown = "teardown",

    -- request
    build_parameters = "form_parameters",
    build_messages = "form_messages",
    build_tools = "form_tools",
    build_body = "set_body",
    build_reasoning = "form_reasoning",

    -- response
    parse_chat = "chat_output",
    parse_inline = "inline_output",
    parse_tokens = "tokens",

    -- tools
    format_calls = "format_tool_calls",
    format_response = "output_response",
  }

  local old_name = old_names[name] or name

  -- Check tools namespace for backwards compat
  if old_name:match("^format_tool") or old_name == "output_response" or old_name == "output_tool_call" then
    if adapter.handlers.tools then
      return adapter.handlers.tools[old_name]
    end
  end

  return adapter.handlers[old_name]
end

---@class CodeCompanion.HTTPAdapter.Handlers.Lifecycle
---@field setup? fun(self: CodeCompanion.HTTPAdapter): boolean
---@field on_exit? fun(self: CodeCompanion.HTTPAdapter, data: table): nil
---@field teardown? fun(self: CodeCompanion.HTTPAdapter): nil

---@class CodeCompanion.HTTPAdapter.Handlers.Request
---@field build_parameters? fun(self: CodeCompanion.HTTPAdapter, params: table, messages: table): table
---@field build_messages? fun(self: CodeCompanion.HTTPAdapter, messages: table): table
---@field build_tools? fun(self: CodeCompanion.HTTPAdapter, tools: table): table|nil
---@field build_reasoning? fun(self: CodeCompanion.HTTPAdapter, messages: table): nil|{ content: string, _data: table }
---@field build_body? fun(self: CodeCompanion.HTTPAdapter, data: table): table|nil

---@class CodeCompanion.HTTPAdapter.Handlers.Response
---@field parse_chat? fun(self: CodeCompanion.HTTPAdapter, data: string|table, tools?: table): { status: string, output: table }|nil
---@field parse_inline? fun(self: CodeCompanion.HTTPAdapter, data: string|table, context?: table): { status: string, output: string }|nil
---@field parse_tokens? fun(self: CodeCompanion.HTTPAdapter, data: table): number|nil

---@class CodeCompanion.HTTPAdapter.Handlers.Tools
---@field format_calls? fun(self: CodeCompanion.HTTPAdapter, tools: table): table
---@field format_response? fun(self: CodeCompanion.HTTPAdapter, tool_call: table, output: string): table

---@class CodeCompanion.HTTPAdapter.Handlers
---@field lifecycle? CodeCompanion.HTTPAdapter.Handlers.Lifecycle
---@field request? CodeCompanion.HTTPAdapter.Handlers.Request
---@field response? CodeCompanion.HTTPAdapter.Handlers.Response
---@field tools? CodeCompanion.HTTPAdapter.Handlers.Tools
---@field resolve? fun(self: CodeCompanion.HTTPAdapter): nil (Deprecated: use lifecycle.setup)
---@field setup? fun(self: CodeCompanion.HTTPAdapter): boolean (Deprecated: use lifecycle.setup)
---@field set_body? fun(self: CodeCompanion.HTTPAdapter, data: table): table|nil (Deprecated: use request.build_body)
---@field form_parameters? fun(self: CodeCompanion.HTTPAdapter, params: table, messages: table): table (Deprecated: use request.build_parameters)
---@field form_messages? fun(self: CodeCompanion.HTTPAdapter, messages: table): table (Deprecated: use request.build_messages)
---@field form_reasoning? fun(self: CodeCompanion.HTTPAdapter, messages: table): nil|{ content: string, _data: table } (Deprecated: use request.build_reasoning)
---@field form_tools? fun(self: CodeCompanion.HTTPAdapter, tools: table): table (Deprecated: use request.build_tools)
---@field tokens? fun(self: CodeCompanion.HTTPAdapter, data: table): number|nil (Deprecated: use response.parse_tokens)
---@field chat_output? fun(self: CodeCompanion.HTTPAdapter, data: table, tools: table): table|nil (Deprecated: use response.parse_chat)
---@field inline_output? fun(self: CodeCompanion.HTTPAdapter, data: table, context: table): table|nil (Deprecated: use response.parse_inline)
---@field on_exit? fun(self: CodeCompanion.HTTPAdapter, data: table): table|nil (Deprecated: use lifecycle.on_exit)
---@field teardown? fun(self: CodeCompanion.HTTPAdapter): any (Deprecated: use lifecycle.teardown)

---@class CodeCompanion.HTTPAdapter
---@field name string The name of the adapter
---@field type string|"http" The type of the adapter, e.g. "http" or "acp"
---@field formatted_name string The formatted name of the adapter
---@field available_tools? table The tools that are available for the adapter
---@field roles table The mapping of roles in the config to the LLM's defined roles
---@field features table The features that the adapter supports
---@field url string The URL of the generative AI service to connect to
---@field env? table Environment variables which can be referenced in the parameters
---@field env_replaced? table Replacement of environment variables with their actual values
---@field headers table The headers to pass to the request
---@field parameters table The parameters to pass to the request
---@field body table Additional body parameters to pass to the request
---@field temp? table A table to store temporary values which are not passed to the request
---@field raw? table Any additional curl arguments to pass to the request
---@field opts? table Additional options for the adapter
---@field model? { name: string, formatted_name?: string, vendor?: string, opts: table } The model to use for the request
---@field handlers CodeCompanion.HTTPAdapter.Handlers Functions which link the output from the request to CodeCompanion
---@field schema table Set of parameters for the generative AI service that the user can customise in the chat buffer
---@field methods table Methods that the adapter can perform e.g. for Slash Commands

---@class CodeCompanion.HTTPAdapter.Safe
---@field name string The name of the adapter
---@field model string The current model name
---@field available_tools? table The tools that are available for the adapter
---@field formatted_name string The formatted name of the adapter
---@field features table The features that the adapter supports
---@field url string The URL of the generative AI service to connect to
---@field headers table The headers to pass to the request
---@field parameters table The parameters to pass to the request
---@field opts? table Additional options for the adapter
---@field handlers CodeCompanion.HTTPAdapter.Handlers Functions which link the output from the request to CodeCompanion
---@field schema table Set of parameters for the generative AI service that the user can customise in the chat buffer

---@class CodeCompanion.HTTPAdapter
local Adapter = {}

Adapter.get_handler = get_handler
Adapter.uses_new_handlers = uses_new_handlers

---@return CodeCompanion.HTTPAdapter
function Adapter.new(args)
  return setmetatable(args, { __index = Adapter })
end

---Get the default settings from the schema
---@return table
function Adapter:make_from_schema()
  local settings = {}

  -- Process regular schema values
  for key, value in pairs(self.schema) do
    if type(value.condition) == "function" and not value.condition(self) then
      goto continue
    end

    local default = value.default
    if default ~= nil then
      if type(default) == "function" then
        default = default(self)
      end
      settings[key] = default
    end

    ::continue::
  end

  return settings
end

---Set parameters based on the schema table's mappings
---@param settings? table
---@return CodeCompanion.HTTPAdapter
function Adapter:map_schema_to_params(settings)
  settings = settings or self:make_from_schema()

  for k, v in pairs(settings) do
    local mapping = self.schema[k] and self.schema[k].mapping
    if mapping then
      -- Parse the mapping path
      local mapping_segments = {}
      for segment in string.gmatch(mapping, "[^.]+") do
        table.insert(mapping_segments, segment)
      end

      -- Navigate to the mapping location
      local current = self
      for i = 1, #mapping_segments do
        if not current[mapping_segments[i]] then
          current[mapping_segments[i]] = {}
        end
        current = current[mapping_segments[i]]
      end

      -- Parse the schema key for nested structure (e.g., "reasoning.effort")
      local key_segments = {}
      for segment in string.gmatch(k, "[^.]+") do
        table.insert(key_segments, segment)
      end

      -- Create nested structure based on the key segments
      for i = 1, #key_segments - 1 do
        if not current[key_segments[i]] then
          current[key_segments[i]] = {}
        end
        current = current[key_segments[i]]
      end

      -- Set the final value at the deepest level
      current[key_segments[#key_segments]] = v
    end
  end

  return self
end

Adapter.map_roles = shared.map_roles

---Extend an existing adapter
---@param adapter table|string|function
---@param opts? table
---@return CodeCompanion.HTTPAdapter
function Adapter.extend(adapter, opts)
  local ok
  local adapter_config
  opts = opts or {}

  if type(adapter) == "string" then
    ok, adapter_config = pcall(require, "codecompanion.adapters.http." .. adapter)
    if not ok then
      -- TODO: Remove this in v18.0.0
      -- START

      -- Try new structure first
      if config.adapters.http and config.adapters.http[adapter] then
        adapter_config = config.adapters.http[adapter]
      else
        -- Fallback to root level for backwards compatibility
        adapter_config = config.adapters[adapter]
      end
      -- END

      --TODO: Uncomment this in v18.0.0
      --adapter_config = config.adapters.http[adapter]

      if adapter_config and type(adapter_config) == "function" then
        adapter_config = adapter_config()
      end
    end
  elseif type(adapter) == "function" then
    adapter_config = adapter()
  else
    adapter_config = adapter
  end

  -- Ensure we have a valid adapter_config before deep extending
  if not adapter_config then
    return log:error("[adapters::http::extend] Adapter not found: %s", adapter)
  end

  adapter_config = vim.tbl_deep_extend("force", {}, vim.deepcopy(adapter_config), opts or {})
  if not adapter_config.type then
    adapter_config.type = "http"
  end

  return Adapter.new(adapter_config)
end

---Set the model name and options on the adapter for convenience
---@param adapter CodeCompanion.HTTPAdapter
---@return CodeCompanion.HTTPAdapter
function Adapter.set_model(adapter)
  -- Set the model dictionary as a convenience for the user. This can be string
  -- or function values. If they're functions, these are likely to make http
  -- requests to obtain a list of available models. This is expensive, so
  -- we dont't execute them here. Instead, let the user decide when to.
  if adapter.schema and adapter.schema.model then
    adapter.model = {}
    local model = adapter.schema.model.default
    local choices = adapter.schema.model.choices

    if type(model) == "string" then
      adapter.model.name = model
    end
    if type(choices) == "table" then
      adapter.model.opts = (choices[model] and choices[model].opts) and choices[model].opts
    end
  end

  return adapter
end

---Resolve an adapter from deep within the plugin...somewhere
---@param adapter? CodeCompanion.HTTPAdapter|string|function
---@param opts? table
---@return CodeCompanion.HTTPAdapter
function Adapter.resolve(adapter, opts)
  adapter = adapter or config.strategies.chat.adapter
  opts = opts or {}

  if type(adapter) == "table" then
    if adapter.name and adapter.schema and Adapter.resolved(adapter) then
      log:trace("[adapters:http:resolve] Returning existing resolved adapter: %s", adapter.name)
      return Adapter.set_model(adapter)
    elseif adapter.name and adapter.model then
      log:trace("[adapters:http:resolve] Table adapter: %s", adapter.name)
      local model_name = type(adapter.model) == "table" and adapter.model.name or adapter.model
      return Adapter.resolve(adapter.name, { model = model_name })
    end
    adapter = Adapter.new(adapter)
  elseif type(adapter) == "string" then
    log:trace(
      "[adapters:http:resolve] Loading adapter: %s%s",
      adapter,
      opts.model and (" with model: " .. opts.model) or ""
    )
    opts = vim.tbl_deep_extend("force", opts, { name = adapter })
    if opts.model then
      opts = vim.tbl_deep_extend("force", opts, {
        schema = {
          model = {
            default = opts.model,
          },
        },
      })
    end
    adapter = Adapter.extend(config.adapters.http[adapter] or adapter, opts)
  elseif type(adapter) == "function" then
    adapter = adapter()
  end

  if not adapter.type then
    adapter.type = "http"
  end

  if adapter.handlers and adapter.handlers.resolve then
    adapter.handlers.resolve(adapter)
  end

  return Adapter.set_model(adapter)
end

---Check if an adapter has already been resolved
---@param adapter CodeCompanion.HTTPAdapter|string|function|nil
---@return boolean
function Adapter.resolved(adapter)
  if adapter and getmetatable(adapter) and getmetatable(adapter).__index == Adapter then
    return true
  end
  return false
end

---Make an adapter safe for serialization and prevent any recursive issues.
---Adapters have become complex, making API calls to get models etc.
---@param adapter CodeCompanion.HTTPAdapter
---@return CodeCompanion.HTTPAdapter.Safe
function Adapter.make_safe(adapter)
  return {
    name = adapter.name,
    model = adapter.model,
    available_tools = adapter.available_tools,
    formatted_name = adapter.formatted_name,
    features = adapter.features,
    url = adapter.url,
    headers = adapter.headers,
    parameters = adapter.parameters,
    opts = adapter.opts,
    handlers = adapter.handlers,
    schema = vim
      .iter(adapter.schema)
      :filter(function(n, _)
        if n == "model" then
          return false
        end
        return true
      end)
      :totable(),
  }
end

return Adapter
