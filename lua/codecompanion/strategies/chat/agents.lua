local config = require("codecompanion").config
local log = require("codecompanion.utils.log")

local _CONSTANTS = {
  PREFIX = "@",
}

---Look for agents in a given message
---@param message string
---@param agents table
---@return table|nil
local function find(message, agents)
  local found = {}
  for agent, _ in pairs(agents) do
    if message:match("%f[%w" .. _CONSTANTS.PREFIX .. "]" .. _CONSTANTS.PREFIX .. agent .. "%f[%W]") then
      table.insert(found, agent)
    end
  end

  if #found == 0 then
    return nil
  end

  return found
end

---@param agent table
---@return CodeCompanion.Agent|nil
local function resolve(agent)
  local callback = agent.callback
  local ok, module = pcall(require, "codecompanion." .. callback)

  -- User has specified a custom callback
  if not ok then
    log:trace("Calling agent: %s", callback)
    return require(callback)
  end

  log:trace("Calling agent: %s", callback)
  return module
end

---@class CodeCompanion.Agents
---@field agents table
local Agents = {}

---@param args? table
function Agents.new(args)
  local self = setmetatable({
    agents = config.strategies.agent.agents,
    args = args,
  }, { __index = Agents })

  return self
end

---Parse a message to detect if it references any agents
---@param message string
---@return table|nil
function Agents:parse(message)
  local agents = find(message, self.agents)
  if not agents then
    return
  end

  local output = {}

  for _, agent in ipairs(agents) do
    output[agent] = resolve(self.agents[agent])
  end

  log:trace("Agent(s) output: %s", output)

  return output
end

---Replace the agent tag in a given message
---@param message string
---@param agent string
---@return string
function Agents:replace(message, agent)
  agent = _CONSTANTS.PREFIX .. agent
  return vim.trim(message:gsub(agent, ""))
end

return Agents
