local config = require("codecompanion").config
local log = require("codecompanion.utils.log")

local _CONSTANTS = {
  PREFIX = "@",
}

---Look for tools in a given message
---@param message string
---@param tools table
---@return table|nil
local function find(message, tools)
  local found = {}
  for tool, _ in pairs(tools) do
    if message:match("%f[%w" .. _CONSTANTS.PREFIX .. "]" .. _CONSTANTS.PREFIX .. tool .. "%f[%W]") then
      table.insert(found, tool)
    end
  end

  if #found == 0 then
    return nil
  end

  return found
end

---@param tool table
---@return CodeCompanion.Agent|nil
local function resolve(tool)
  local callback = tool.callback
  local ok, module = pcall(require, "codecompanion." .. callback)

  -- User has specified a custom callback
  if not ok then
    log:trace("Calling tool: %s", callback)
    return require(callback)
  end

  log:trace("Calling tool: %s", callback)
  return module
end

---@class CodeCompanion.Tools
---@field tools table
local Tools = {}

---@param args? table
function Tools.new(args)
  local self = setmetatable({
    tools = config.strategies.agent.tools,
    args = args,
  }, { __index = Tools })

  return self
end

---Parse a message to detect if it references any tools
---@param message string
---@return table|nil
function Tools:parse(message)
  local tools = find(message, self.tools)
  if not tools then
    return
  end

  local output = {}

  for _, tool in ipairs(tools) do
    output[tool] = resolve(self.tools[tool])
  end

  log:trace("tool(s) output: %s", output)

  return output
end

---Replace the tool tag in a given message
---@param message string
---@param tool string
---@return string
function Tools:replace(message, tool)
  tool = _CONSTANTS.PREFIX .. tool
  return vim.trim(message:gsub(tool, ""))
end

return Tools
