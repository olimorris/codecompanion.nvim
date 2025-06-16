--[[
Methods for handling interactions between the chat buffer and tools
--]]

---@class CodeCompanion.Chat.Tools
---@field chat CodeCompanion.Chat
---@field flags table Flags that external functions can update and subscribers can interact with
---@field in_use table<string, boolean> Tools that are in use on the chat buffer
---@field schemas table<string, table> The config for the tools in use

---@class CodeCompanion.Chat.Tools
local Tools = {}

local config = require("codecompanion.config")
local util = require("codecompanion.utils")

---@class CodeCompanion.Chat.ToolsArgs
---@field chat CodeCompanion.Chat

---@param args CodeCompanion.Chat.ToolsArgs
function Tools.new(args)
  local self = setmetatable({
    chat = args.chat,
    flags = {},
    in_use = {},
    schemas = {},
  }, { __index = Tools })

  return self
end

---Add a reference to the tool in the chat buffer
---@param chat CodeCompanion.Chat The chat buffer
---@param id string The id of the tool
---@param opts? table Optional parameters for the reference
---@return nil
local function add_reference(chat, id, opts)
  chat.references:add({
    source = "tool",
    name = "tool",
    id = id,
    opts = opts,
  })
end

---Add the tool's system prompt to the chat buffer
---@param chat CodeCompanion.Chat The chat buffer
---@param tool table the resolved tool
---@param id string The id of the tool
---@return nil
local function add_system_prompt(chat, tool, id)
  if tool and tool.system_prompt then
    local system_prompt
    if type(tool.system_prompt) == "function" then
      system_prompt = tool.system_prompt(tool.schema)
    elseif type(tool.system_prompt) == "string" then
      system_prompt = tostring(tool.system_prompt)
    end
    chat:add_message(
      { role = config.constants.SYSTEM_ROLE, content = system_prompt },
      { visible = false, tag = "tool", reference = id }
    )
  end
end

---Add the tool's schema to the chat buffer
---@param self CodeCompanion.Chat.Tools The tools object
---@param tool table The resolved tool
---@param id string The id of the tool
---@return nil
local function add_schema(self, tool, id)
  self.schemas[id] = tool.schema
end

---Add the given tool to the chat buffer
---@param tool string The name of the tool
---@param tool_config table The tool from the config
---@param opts? table Optional parameters
---@return nil
function Tools:add(tool, tool_config, opts)
  opts = opts or {
    visible = true,
  }
  local resolved_tool = self.chat.agents.resolve(tool_config)
  if not resolved_tool or self.in_use[tool] then
    return
  end

  local id = "<tool>" .. tool .. "</tool>"
  add_reference(self.chat, id, opts)
  add_system_prompt(self.chat, resolved_tool, id)
  add_schema(self, resolved_tool, id)

  util.fire("ChatToolAdded", { bufnr = self.chat.bufnr, id = self.chat.id, tool = tool })

  self.in_use[tool] = true

  return self
end

---Add tools from a group to the chat buffer
---@param group string The name of the group
---@param tools_config table The tools configuration
---@return nil
function Tools:add_group(group, tools_config)
  local group_config = tools_config.groups[group]
  if not group_config or not group_config.tools then
    return
  end

  local opts = vim.tbl_deep_extend("force", { collapse_tools = true }, group_config.opts or {})
  local collapse_tools = opts.collapse_tools

  local group_id = "<group>" .. group .. "</group>"

  local system_prompt = group_config.system_prompt
  if type(system_prompt) == "function" then
    system_prompt = system_prompt(group_config)
  end
  if system_prompt then
    self.chat:add_message({
      role = config.constants.SYSTEM_ROLE,
      content = system_prompt,
    }, { tag = "tool", visible = false, reference = group_id })
  end

  if collapse_tools then
    add_reference(self.chat, group_id)
  end
  for _, tool in ipairs(group_config.tools) do
    self:add(tool, tools_config[tool], { visible = not collapse_tools })
  end
end

---Determine if the chat buffer has any tools in use
---@return boolean
function Tools:loaded()
  return not vim.tbl_isempty(self.in_use)
end

---Clear the tools
---@return nil
function Tools:clear()
  self.flags = {}
  self.in_use = {}
  self.schemas = {}
end

return Tools
