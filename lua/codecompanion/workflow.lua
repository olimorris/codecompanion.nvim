local config = require("codecompanion").config
local log = require("codecompanion.utils.log")

---@class CodeCompanion.Workflow
local Workflow = {}

---@class CodeCompanion.WorkflowArgs
---@field context table
---@field strategy string

---@param args table
---@return CodeCompanion.Workflow
function Workflow.new(args)
  return setmetatable(args, { __index = Workflow })
end

---@param prompts table
function Workflow:workflow(prompts)
  log:trace("Initiating workflow")

  local starting_prompts = {}
  local workflow_prompts = {}

  for _, prompt in ipairs(prompts) do
    if prompt.start then
      if
        (type(prompt.condition) == "function" and not prompt.condition())
        or (prompt.contains_code and not config.send_code)
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

  local function send_prompt(chat)
    log:trace("Sending agentic prompt to chat buffer")

    if #workflow_prompts == 0 then
      return
    end

    local prompt = workflow_prompts[1]
    chat:add_message(prompt)

    if prompt.auto_submit then
      chat:submit()
    end

    return table.remove(workflow_prompts, 1)
  end

  local chat = require("codecompanion.strategies.chat").new({
    type = "chat",
    messages = starting_prompts,
    show_buffer = true,
  })

  if not chat then
    return
  end

  local group = vim.api.nvim_create_augroup("CodeCompanionWorkflow", {
    clear = false,
  })

  vim.api.nvim_create_autocmd("User", {
    desc = "Listen for CodeCompanion agent messages",
    group = group,
    pattern = "CodeCompanionChat",
    callback = function(request)
      if request.buf ~= chat.bufnr or request.data.status ~= "finished" then
        return
      end

      send_prompt(chat)

      if #workflow_prompts == 0 then
        vim.api.nvim_del_augroup_by_id(group)
      end
    end,
  })
end

return Workflow
