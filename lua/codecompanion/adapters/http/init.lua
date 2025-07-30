local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local shared = require("codecompanion.adapters.shared")
local utils = require("codecompanion.utils.adapters")

---@class CodeCompanion.HTTPAdapter
---@field name string The name of the adapter
---@field type string|"http" The type of the adapter, e.g. "http" or "acp"
---@field formatted_name string The formatted name of the adapter
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
---@field model? { name: string, opts: table } The model to use for the request
---@field handlers table Functions which link the output from the request to CodeCompanion
---@field handlers.setup? fun(self: CodeCompanion.HTTPAdapter): boolean
---@field handlers.set_body? fun(self: CodeCompanion.HTTPAdapter, data: table): table|nil
---@field handlers.form_parameters fun(self: CodeCompanion.HTTPAdapter, params: table, messages: table): table
---@field handlers.form_messages fun(self: CodeCompanion.HTTPAdapter, messages: table): table
---@field handlers.form_reasoning? fun(self: CodeCompanion.HTTPAdapter, messages: table): nil|{ content: string, _data: table }
---@field handlers.form_tools? fun(self: CodeCompanion.HTTPAdapter, tools: table): table
---@field handlers.tokens? fun(self: CodeCompanion.HTTPAdapter, data: table): number|nil
---@field handlers.chat_output fun(self: CodeCompanion.HTTPAdapter, data: table, tools: table): table|nil
---@field handlers.inline_output fun(self: CodeCompanion.HTTPAdapter, data: table, context: table): table|nil
---@field handlers.tools.format? fun(self: CodeCompanion.HTTPAdapter, tools: table): table
---@field handlers.tools.output_tool_call? fun(self: CodeCompanion.HTTPAdapter, tool_call: table, output: string): table
---@field handlers.on_exit? fun(self: CodeCompanion.HTTPAdapter, data: table): table|nil
---@field handlers.teardown? fun(self: CodeCompanion.HTTPAdapter): any
---@field schema table Set of parameters for the generative AI service that the user can customise in the chat buffer
---@field methods table Methods that the adapter can perform e.g. for Slash Commands

---@class CodeCompanion.HTTPAdapter
local Adapter = {}

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
      local segments = {}
      for segment in string.gmatch(mapping, "[^.]+") do
        table.insert(segments, segment)
      end

      local current = self
      for i = 1, #segments - 1 do
        if not current[segments[i]] then
          current[segments[i]] = {}
        end
        current = current[segments[i]]
      end

      -- Before setting the value, ensure the target exists or initialize it.
      local target = segments[#segments]
      if not current[target] then
        current[target] = {}
      end

      -- Ensure 'target' is not nil and 'k' can be assigned to the final segment.
      if target then
        current[target][k] = v
      end
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
      -- Try new structure first
      if config.adapters.http and config.adapters.http[adapter] then
        adapter_config = config.adapters.http[adapter]
      else
        -- Fallback to root level for backwards compatibility
        adapter_config = config.adapters[adapter]
      end

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
    return log:error("Adapter not found: %s", adapter)
  end

  adapter_config = vim.tbl_deep_extend("force", {}, vim.deepcopy(adapter_config), opts or {})

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

  -- Helper function to get adapter from config with backwards compatibility
  local function get_adapter_from_config(name)
    -- Try new structure first
    if config.adapters.http and config.adapters.http[name] then
      return config.adapters.http[name]
    end
    -- Fallback to root level for backwards compatibility
    return config.adapters[name]
  end

  if type(adapter) == "table" then
    if adapter.name and adapter.schema and Adapter.resolved(adapter) then
      log:trace("[HTTP Adapter] Returning existing resolved adapter: %s", adapter.name)
      return Adapter.set_model(adapter)
    elseif adapter.name and adapter.model then
      log:trace("[HTTP Adapter] Table adapter: %s", adapter.name)
      local model_name = type(adapter.model) == "table" and adapter.model.name or adapter.model
      return Adapter.resolve(adapter.name, { model = model_name })
    end
    adapter = Adapter.new(adapter)
  elseif type(adapter) == "string" then
    log:trace("[HTTP Adapter] Loading adapter: %s%s", adapter, opts.model and (" with model: " .. opts.model) or "")
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

    local config_adapter = get_adapter_from_config(adapter)
    adapter = Adapter.extend(config_adapter or adapter, opts)
  elseif type(adapter) == "function" then
    adapter = adapter()
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

---Make an adapter safe for serialization
---@param adapter CodeCompanion.HTTPAdapter
---@return table
function Adapter.make_safe(adapter)
  return {
    name = adapter.name,
    model = adapter.model,
    formatted_name = adapter.formatted_name,
    features = adapter.features,
    url = adapter.url,
    headers = adapter.headers,
    params = adapter.parameters,
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
