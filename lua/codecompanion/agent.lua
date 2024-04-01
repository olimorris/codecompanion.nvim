local config = require("codecompanion.config")

---@class CodeCompanion.Agent
local Agent = {}

---@class CodeCompanion.AgentArgs
---@field context table
---@field strategy string

---@param args table
---@return CodeCompanion.Agent
function Agent.new(args)
  return setmetatable(args, { __index = Agent })
end

---@param prompts table
function Agent:workflow(prompts)
  local starting_prompts = {}
  local workflow_prompts = {}

  for _, prompt in ipairs(prompts) do
    if prompt.start then
      if
        (type(prompt.condition) == "function" and not prompt.condition())
        or (prompt.contains_code and not config.options.send_code)
      then
        goto continue
      end

      table.insert(starting_prompts, {
        role = prompt.role,
        content = prompt.content,
      })
    else
      table.insert(workflow_prompts, {
        role = prompt.role,
        content = prompt.content,
        auto_submit = prompt.auto_submit,
      })
    end
    ::continue::
  end

  return require("codecompanion.strategies.chat").new({
    type = "chat",
    messages = starting_prompts,
    workflow = workflow_prompts,
    show_buffer = true,
  })
end

return Agent
