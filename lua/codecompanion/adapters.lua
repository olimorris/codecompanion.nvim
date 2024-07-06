local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils.util")

---@class CodeCompanion.Adapter
---@field args CodeCompanion.AdapterArgs
local Adapter = {}

---@class CodeCompanion.AdapterArgs
---@field name string The name of the adapter
---@field features table The features that the adapter supports
---@field url string The URL of the generative AI service to connect to
---@field env? table Environment variables which can be referenced in the parameters
---@field headers table The headers to pass to the request
---@field parameters table The parameters to pass to the request
---@field chat_prompt string The system chat prompt to send to the LLM
---@field raw? table Any additional curl arguments to pass to the request
---@field opts? table Additional options for the adapter
---@field callbacks table Functions which link the output from the request to CodeCompanion
---@field callbacks.form_parameters fun()
---@field callbacks.form_messages fun()
---@field callbacks.is_complete fun()
---@field callbacks.chat_output fun()
---@field callbacks.inline_output fun()
---@field schema table Set of parameters for the generative AI service that the user can customise in the chat buffer

---@param args CodeCompanion.AdapterArgs
---@return CodeCompanion.Adapter
function Adapter.new(args)
  return setmetatable({ args = args }, { __index = Adapter })
end

---@return table
function Adapter:get_default_settings()
  local settings = {}

  for key, value in pairs(self.args.schema) do
    if value.default ~= nil then
      settings[key] = value.default
    end
  end

  return settings
end

---@param settings? table
---@return CodeCompanion.Adapter
function Adapter:set_params(settings)
  if not settings then
    settings = self:get_default_settings()
  end

  for k, v in pairs(settings) do
    local mapping = self.args.schema[k] and self.args.schema[k].mapping
    if mapping then
      local segments = {}
      for segment in string.gmatch(mapping, "[^.]+") do
        table.insert(segments, segment)
      end

      local current = self.args
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

---@return CodeCompanion.Adapter
function Adapter:replace_header_vars()
  if self.args.headers then
    for k, v in pairs(self.args.headers) do
      self.args.headers[k] = v:gsub("${(.-)}", function(var)
        local env_var_or_cmd = self.args.env[var]

        if not env_var_or_cmd then
          log:error("Error: Could not find env var or command: %s", self.args.env[var])
          return vim.notify(
            string.format("[CodeCompanion.nvim]\nCould not find env var or command: %s", self.args.env[var]),
            vim.log.levels.ERROR
          )
        end

        if utils.is_cmd_var(env_var_or_cmd) then
          log:trace("Detected cmd in environment variable")
          local command = env_var_or_cmd:sub(5)
          local handle = io.popen(command, "r")
          if handle then
            local result = handle:read("*a")
            log:trace("Executed command: %s", command)
            handle:close()
            return result:gsub("%s+$", "")
          else
            log:error("Error: Could not execute command: %s", command)
            return vim.notify(
              string.format("[CodeCompanion.nvim]\nCould not execute command: %s", command),
              vim.log.levels.ERROR
            )
          end
        end

        local env_var = os.getenv(env_var_or_cmd)
        if not env_var then
          log:error("Error: Could not find env var: %s", self.args.env[var])
          return vim.notify(
            string.format("[CodeCompanion.nvim]\nCould not find env var: %s", self.args.env[var]),
            vim.log.levels.ERROR
          )
        end
        return env_var
      end)
    end
  end

  return self
end

function Adapter.use(adapter, opts)
  local adapter_config

  if type(adapter) == "string" then
    adapter_config = require("codecompanion.adapters." .. adapter)
  elseif type(adapter) == "function" then
    adapter_config = adapter()
  else
    adapter_config = adapter
  end

  if opts then
    adapter_config = vim.tbl_deep_extend("force", {}, vim.deepcopy(adapter_config), opts or {})
  end

  return Adapter.new(adapter_config)
end

return Adapter
