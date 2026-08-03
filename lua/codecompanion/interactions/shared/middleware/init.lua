local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local M = {}

local resolved = {}

---Resolve a middleware config value to a format function
---@param value function|string
---@return function|nil
local function resolve(value)
  if type(value) == "function" then
    return value
  end
  if type(value) ~= "string" then
    return nil
  end
  if resolved[value] then
    return resolved[value]
  end

  local ok, module = pcall(require, value)
  if not ok or type(module) ~= "table" or type(module.format) ~= "function" then
    log:error("[middleware] Could not resolve `%s`", value)
    return nil
  end

  resolved[value] = module.format
  return module.format
end

---Get the middleware registered for a file's extension
---@param path string
---@return function|nil
local function for_file(path)
  local extension = path:match("%.([^.]+)$")
  if not extension or type(config.middleware) ~= "table" then
    return nil
  end

  return resolve(config.middleware[extension:lower()])
end

---Format content with any middleware registered for the file's extension
---@param args { path: string, raw: string }
---@return string content
---@return boolean formatted
function M.apply(args)
  local format = for_file(args.path)
  if not format then
    return args.raw, false
  end

  local ok, formatted = pcall(format, args.raw, args.path)
  if not ok then
    log:error("[middleware] Could not format `%s`: %s", args.path, formatted)
    return args.raw, false
  end
  if type(formatted) ~= "string" then
    return args.raw, false
  end

  return formatted, true
end

return M
