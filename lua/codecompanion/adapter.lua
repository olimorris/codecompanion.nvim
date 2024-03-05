local log = require("codecompanion.utils.log")

---@class CodeCompanion.Adapter
---@field name string
---@field url string
---@field env? table
---@field raw? table
---@field header table
---@field parameters table
---@field callbacks table
---@field schema table
local Adapter = {}

---@class CodeCompanion.AdapterArgs
---@field name string
---@field url string
---@field env? table
---@field raw? table
---@field header table
---@field parameters table
---@field callbacks table
---@field schema table

---@param args table
---@return CodeCompanion.Adapter
function Adapter.new(args)
  return setmetatable(args, { __index = Adapter })
end

---@return table
function Adapter:get_default_settings()
  local settings = {}

  for key, value in pairs(self.schema) do
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

---@return CodeCompanion.Adapter
function Adapter:replace_header_vars()
  if self.headers then
    for k, v in pairs(self.headers) do
      self.headers[k] = v:gsub("${(.-)}", function(var)
        local env_var = self.env[var]

        if env_var then
          env_var = os.getenv(env_var)
          if not env_var then
            log:error("Error: Could not find env var: %s", self.env[var])
            return vim.notify(
              string.format("[CodeCompanion.nvim]\nCould not find env var: %s", self.env[var]),
              vim.log.levels.ERROR
            )
          end
          return env_var
        end
      end)
    end
  end

  return self
end

return Adapter
