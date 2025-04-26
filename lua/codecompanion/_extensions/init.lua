---@class CodeCompanion.Extensions
local Extensions = {
  ---@type table<string,any> Extension exports
  _exports = {},
}

Extensions.manager = setmetatable({}, {
  __index = function(_, key)
    return Extensions._exports[key] or {}
  end,
})
---Resolves extension from "codecompanion._extensions.<name>" from the runtimepath including third-party extensions
---Can also provide a path to a local extension in the config
---@param name string The name of the extension
---@param callback string | table | function T
---@return table|nil
function Extensions.resolve(name, callback)
  local extension
  --if callback is given, resolve from string or function
  if callback then
    if type(callback) == "string" then
      extension = require(callback)
    elseif type(callback) == "function" then
      extension = callback()
    elseif type(callback) == "table" then
      extension = callback
    else
      error("Codecompanion extension " .. name .. " callback is not a string, table or function")
    end
  else
    -- Load the extension from the runtimepath
    extension = require("codecompanion._extensions." .. name)
  end
  -- Check if the extension is a table and has a setup function
  if type(extension) ~= "table" then
    error("Codecompanion extension " .. name .. " is not a table")
  end
  if type(extension.setup) ~= "function" then
    error("Codecompanion extension " .. name .. " does not have a setup function")
  end
  return extension
end

---Resolve extension from given path or from runtimepath and loads it
---@param name string The name of the extension
---@param schema {enabled?: boolean, opts?: table, callback?: table | function } The extension config
---@return table | nil
function Extensions.load_extension(name, schema)
  schema = schema or {}
  local ext = Extensions.resolve(name, schema.callback)
  if ext then
    ext.setup(schema.opts or {})
    -- Store exports if any
    if ext.exports then
      Extensions._exports[name] = ext.exports
    end
    return ext
  end
end

return Extensions
