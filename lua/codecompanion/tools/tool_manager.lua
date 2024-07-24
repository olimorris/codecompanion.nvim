---@class CodeCompanion.ToolManager
---@field tools CodeCompanion.CopilotTool[]
local ToolManager = {}
ToolManager.__index = ToolManager

function ToolManager.new()
  local self = setmetatable({}, ToolManager)
  self.tools = {}
  return self
end

function ToolManager:register_tool(name, tool)
  self.tools[name] = tool
end

function ToolManager:get_tool(name)
  return self.tools[name]
end

function ToolManager:get_tool_descriptions()
  local descriptions = {}
  for name, tool in pairs(self.tools) do
    descriptions[name] = {
      description = tool:description(),
      input_format = tool:input_format(),
      output_format = tool:output_format(),
    }
  end
  return descriptions
end

function ToolManager:get_tool_examples()
  local examples = {}
  for name, tool in pairs(self.tools) do
    examples[name] = tool:example()
  end
  return examples
end

return ToolManager
