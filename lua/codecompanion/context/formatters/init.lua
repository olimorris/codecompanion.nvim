local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local M = {}

local resolved = {}

---Resolve a formatter config value to a format function
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
    log:error("[context.formatters] Could not resolve `%s`", value)
    return nil
  end

  resolved[value] = module.format
  return module.format
end

---Get the formatter registered for a file's extension
---@param path string
---@return function|nil
local function for_file(path)
  local extension = path:match("%.([^.]+)$")
  local formatters = config.context and config.context.formatters
  if not extension or type(formatters) ~= "table" then
    return nil
  end

  return resolve(formatters[extension:lower()])
end

---Format content with the formatter registered for the file's extension
---@param args { path: string, raw: string }
---@return string content
---@return boolean Was the content formatted?
function M.apply(args)
  local format = for_file(args.path)
  if not format then
    return args.raw, false
  end

  local ok, formatted = pcall(format, args.raw, args.path)
  if not ok then
    log:error("[context.formatters] Could not format `%s`: %s", args.path, formatted)
    return args.raw, false
  end
  if type(formatted) ~= "string" then
    return args.raw, false
  end

  return formatted, true
end

return M
