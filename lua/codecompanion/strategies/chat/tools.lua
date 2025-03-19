--[[
Methods for handling interactions between the chat buffer and tools
--]]

---@class CodeCompanion.Chat.Tools
---@field chat CodeCompanion.Chat
---@field flags table Flags that external functions can update and subscribers can interact with
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
    tools_in_use = {},
  }, { __index = Tools })

  return self
end

---Add the given tool to the chat buffer
---@param tool string The name of the tool
---@param tool_config table The tool from the config
---@return nil
function Tools:add(tool, tool_config)
  if self.tools_in_use[tool] then
    return
  end

  local id = "<tool>" .. tool .. "</tool>"
  self.chat.references:add({
    source = "tool",
    name = "tool",
    id = id,
  })

  self.tools_in_use[tool] = true

  -- Add the tool's system prompt
  local resolved = self.chat.agents.resolve(tool_config)
  if resolved and resolved.system_prompt then
    local system_prompt
    if type(resolved.system_prompt) == "function" then
      system_prompt = resolved.system_prompt(resolved.schema)
    elseif type(resolved.system_prompt) == "string" then
      system_prompt = tostring(resolved.system_prompt)
    end
    self.chat:add_message(
      { role = config.constants.SYSTEM_ROLE, content = system_prompt },
      { visible = false, tag = "tool", reference = id }
    )
  end

  util.fire("ChatToolAdded", { bufnr = self.chat.bufnr, id = self.chat.id, tool = tool })

  return self
end

---Determine if the chat buffer has any tools in use
---@return boolean
function Tools:loaded()
  return not vim.tbl_isempty(self.tools_in_use)
end

return Tools
