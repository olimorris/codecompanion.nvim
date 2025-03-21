--[[
Methods for handling interactions between the chat buffer and tools
--]]

---@class CodeCompanion.Chat.Tools
---@field chat CodeCompanion.Chat
---@field flags table Flags that external functions can update and subscribers can interact with
---@field schemas table<string, table> The config for the tools in use
---@field tools_in_use table<string, boolean>

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
    schemas = {},
    tools_in_use = {},
  }, { __index = Tools })

  return self
end

---Add a reference to the tool in the chat buffer
---@param chat CodeCompanion.Chat The chat buffer
---@param id string The id of the tool
---@return nil
local function add_reference(chat, id)
  chat.references:add({
    source = "tool",
    name = "tool",
    id = id,
  })
end

---Add the tool's system prompt to the chat buffer
---@param chat CodeCompanion.Chat The chat buffer
---@param tool table the resolved tool
---@return nil
local function add_system_prompt(chat, tool)
  if tool and tool.system_prompt then
    local system_prompt
    if type(tool.system_prompt) == "function" then
      system_prompt = tool.system_prompt(tool.schema)
    elseif type(tool.system_prompt) == "string" then
      system_prompt = tostring(tool.system_prompt)
    end
    chat:add_message(
      { role = config.constants.SYSTEM_ROLE, content = system_prompt },
      { visible = false, tag = "tool", reference = "<tool>" .. tool.name .. "</tool>" }
    )
  end
end

---Add the given tool to the chat buffer
---@param tool string The name of the tool
---@param tool_config table The tool from the config
---@return nil
function Tools:add(tool, tool_config)
  local resolved_tool = self.chat.agents.resolve(tool_config)
  if not resolved_tool or self.tools_in_use[tool] then
    return
  end

  local id = "<tool>" .. tool .. "</tool>"
  add_reference(self.chat, id)
  add_system_prompt(self.chat, resolved_tool)
  self.schemas[tool] = resolved_tool.schema

  util.fire("ChatToolAdded", { bufnr = self.chat.bufnr, id = self.chat.id, tool = tool })

  self.tools_in_use[tool] = true

  return self
end

---Determine if the chat buffer has any tools in use
---@return boolean
function Tools:loaded()
  return not vim.tbl_isempty(self.tools_in_use)
end

return Tools
