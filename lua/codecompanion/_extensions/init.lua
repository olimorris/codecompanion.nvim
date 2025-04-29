---@class CodeCompanion.Extension
---@field setup fun(opts: table): any Function called when extension is loaded
---@field exports? table Optional table of functions exposed via codecompanion.extensions.name

---@class CodeCompanion.Extensions
---@field _exports table<string,table> Extension exports storage
local Extensions = {
  _exports = {},
}

---@type table
Extensions.manager = setmetatable({}, {
  __index = function(_, key)
    -- Return nil for missing extensions instead of empty table
    return Extensions._exports[key]
  end,
})

---Resolves extension from "codecompanion._extensions.<name>" from the runtimepath including third-party extensions
---Can also provide a path to a local extension in the config
---@param name string The name of the extension
---@param callback string|table|function? Optional callback for external extensions
---@return CodeCompanion.Extension|nil
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

  -- Basic validation
  if type(extension) ~= "table" then
    error("Codecompanion extension " .. name .. " is not a table")
  end
  if type(extension.setup) ~= "function" then
    error("Codecompanion extension " .. name .. " does not have a setup function")
  end

  return extension
end

---Register an extension directly
---@param name string The name of the extension
---@param extension CodeCompanion.Extension The extension implementation
---@return nil
function Extensions.register_extension(name, extension)
  return Extensions.load_extension(name, {
    callback = extension,
  })
end

---Resolve extension from given path or from runtimepath and loads it
---@param name string The name of the extension
---@param schema {opts?: table, callback?: string|table|function} The extension config
---@return CodeCompanion.Extension|nil
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
