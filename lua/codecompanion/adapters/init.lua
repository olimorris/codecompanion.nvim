local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

---Check if a variable starts with "cmd:"
---@param var string
---@return boolean
local function is_cmd(var)
  return var:match("^cmd:")
end

---Check if the variable is an environment variable
---@param var string
---@return boolean
local function is_env_var(var)
  local found_var = os.getenv(var)
  if not found_var then
    return false
  end
  return true
end

---Run the command in the environment variable
---@param var string
---@return string|nil
local function run_cmd(var)
  log:trace("Detected cmd in environment variable")
  local cmd = var:sub(5)
  local handle = io.popen(cmd, "r")
  if handle then
    local result = handle:read("*a")
    log:trace("Executed cmd: %s", cmd)
    handle:close()
    return result:gsub("%s+$", "")
  else
    return log:error("Error: Could not execute cmd: %s", cmd)
  end
end

---Get the environment variable
---@param var string
---@return string|nil
local function get_env_var(var)
  log:trace("Fetching environment variable: %s", var)
  return os.getenv(var) or nil
end

---Get the schema value
---@param adapter CodeCompanion.Adapter
---@param var string
---@return string|nil
local function get_schema(adapter, var)
  log:trace("Fetching variable from schema: %s", var)

  local keys = {}
  for key in var:gmatch("[^%.]+") do
    table.insert(keys, key)
  end

  local node = adapter
  for _, key in ipairs(keys) do
    if type(node) ~= "table" then
      return nil
    end
    node = node[key]
    if node == nil then
      return nil
    end
  end

  if not node then
    return
  end

  return node
end

---Replace a variable with its value e.g. "${var}" -> "value"
---@param adapter CodeCompanion.Adapter
---@param str string
---@return string
local function replace_var(adapter, str)
  local pattern = "${(.-)}"

  return str:gsub(pattern, function(var)
    return adapter.env_replaced[var]
  end)
end

---@class CodeCompanion.Adapter
---@field args CodeCompanion.Adapter
local Adapter = {}

---@class CodeCompanion.Adapter
---@field name string The name of the adapter
---@field roles table The mapping of roles in the config to the LLM's defined roles
---@field features table The features that the adapter supports
---@field url string The URL of the generative AI service to connect to
---@field env? table Environment variables which can be referenced in the parameters
---@field env_replaced? table Replacement of environment variables with their actual values
---@field headers table The headers to pass to the request
---@field parameters table The parameters to pass to the request
---@field chat_prompt string The system chat prompt to send to the LLM
---@field raw? table Any additional curl arguments to pass to the request
---@field opts? table Additional options for the adapter
---@field handlers table Functions which link the output from the request to CodeCompanion
---@field handlers.setup? fun(self: CodeCompanion.Adapter): boolean
---@field handlers.set_body? fun(self: CodeCompanion.Adapter, data: table): table|nil
---@field handlers.form_parameters fun(self: CodeCompanion.Adapter, params: table, messages: table): table
---@field handlers.form_messages fun(self: CodeCompanion.Adapter, messages: table): table
---@field handlers.tokens? fun(self: CodeCompanion.Adapter, data: table): number|nil
---@field handlers.chat_output fun(self: CodeCompanion.Adapter, data: table): table|nil
---@field handlers.inline_output fun(self: CodeCompanion.Adapter, data: table, context: table): table|nil
---@field handlers.on_exit? fun(self: CodeCompanion.Adapter, data: table): table|nil
---@field handlers.teardown? fun(self: CodeCompanion.Adapter): any
---@field schema table Set of parameters for the generative AI service that the user can customise in the chat buffer

---@param args CodeCompanion.Adapter
---@return CodeCompanion.Adapter
function Adapter.new(args)
  return setmetatable(args, { __index = Adapter })
end

---TODO: Refactor this to return self so we can chain it
---Get the default settings from the schema
---@return table
function Adapter:get_default_settings()
  local settings = {}

  for key, value in pairs(self.schema) do
    if type(value.condition) == "function" and not value.condition(self.schema) then
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

---Get the variables from the env key of the adapter
---@return CodeCompanion.Adapter
function Adapter:get_env_vars()
  local env_vars = self.env or {}

  if not env_vars then
    return self
  end

  self.env_replaced = {}

  for k, v in pairs(env_vars) do
    if type(v) == "string" and is_cmd(v) then
      self.env_replaced[k] = run_cmd(v)
    elseif type(v) == "string" and is_env_var(v) then
      self.env_replaced[k] = get_env_var(v)
    elseif type(v) == "function" then
      self.env_replaced[k] = v()
    else
      local schema = get_schema(self, v)
      if schema then
        self.env_replaced[k] = schema
      else
        self.env_replaced[k] = v
      end
    end
  end

  return self
end

---Set env vars in a given object in the adapter
---@param object string|table
---@return string|table|nil
function Adapter:set_env_vars(object)
  local obj_copy = vim.deepcopy(object)

  if type(obj_copy) == "string" then
    return replace_var(self, obj_copy)
  elseif type(obj_copy) == "table" then
    local replaced = {}
    for k, v in pairs(obj_copy) do
      if type(v) == "string" then
        replaced[k] = replace_var(self, v)
      else
        replaced[k] = v
      end
    end
    return replaced
  end
end

---Set parameters based on the schema table's mappings
---@param settings? table
---@return CodeCompanion.Adapter
function Adapter:map_schema_to_params(settings)
  if not settings then
    settings = self:get_default_settings()
  end

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

---Replace roles in the messages with the adapter's defined roles
---@param messages table
---@return table
function Adapter:map_roles(messages)
  for _, message in ipairs(messages) do
    if message.role then
      message.role = self.roles[message.role:lower()] or message.role
    end
  end

  return messages
end

---Extend an existing adapter
---@param adapter table|string|function
---@param opts? table
---@return CodeCompanion.Adapter
function Adapter.extend(adapter, opts)
  local adapter_config

  if type(adapter) == "string" then
    adapter_config = require("codecompanion.adapters." .. adapter)
  elseif type(adapter) == "function" then
    adapter_config = adapter()
  else
    adapter_config = adapter
  end

  adapter_config = vim.tbl_deep_extend("force", {}, vim.deepcopy(adapter_config), opts or {})

  return Adapter.new(adapter_config)
end

---Resolve an adapter from deep within the plugin...somewhere
---@param adapter? CodeCompanion.Adapter|string|function
---@return CodeCompanion.Adapter
function Adapter.resolve(adapter)
  adapter = adapter or config.adapters[config.strategies.chat.adapter]

  if type(adapter) == "table" then
    return Adapter.new(adapter)
  elseif type(adapter) == "string" then
    return Adapter.extend(adapter)
  elseif type(adapter) == "function" then
    return adapter()
  end

  return adapter
end

---Make an adapter safe for serialization
---@param adapter CodeCompanion.Adapter
---@return table
function Adapter.make_safe(adapter)
  return {
    name = adapter.name,
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
