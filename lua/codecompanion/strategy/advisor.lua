local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils.util")

---@class CodeCompanion.Advisor
---@field context table
---@field client CodeCompanion.Client
---@field opts table
---@field prompts table
local Advisor = {}

---@class CodeCompanion.AdvisorArgs
---@field context table
---@field client CodeCompanion.Client
---@field opts table
---@field prompts table

---@param opts CodeCompanion.AdvisorArgs
---@return CodeCompanion.Advisor
function Advisor.new(opts)
  log:trace("Initiating Advisor")

  local self = setmetatable({
    context = opts.context,
    client = opts.client,
    opts = opts.opts,
    prompts = opts.prompts,
  }, { __index = Advisor })

  return self
end

---@param user_input string|nil
function Advisor:execute(user_input)
  local conversation = {
    model = self.opts.model,
    messages = {},
  }

  local formatted_messages = {}

  for _, prompt in ipairs(self.prompts) do
    if not prompt.contains_code or (prompt.contains_code and config.options.send_code) then
      if type(prompt.content) == "function" then
        prompt.content = prompt.content(self.context)
      end

      table.insert(formatted_messages, {
        role = prompt.role,
        content = prompt.content,
      })
    end
  end

  -- Add the user prompt last
  if self.opts.user_input and user_input then
    table.insert(formatted_messages, {
      role = "user",
      content = user_input,
    })
  end

  conversation.messages = formatted_messages

  if config.options.send_code and self.opts.send_visual_selection and self.context.is_visual then
    table.insert(conversation.messages, 2, {
      role = "user",
      content = "For context, this is the code I will ask you to help me with:\n\n"
        .. "```"
        .. self.context.filetype
        .. "\n"
        .. table.concat(self.context.lines, "\n")
        .. "\n```",
    })
  end

  local messages = conversation.messages

  if config.options.display.advisor.stream then
    local chat = require("codecompanion.strategy.chat").new({
      client = self.client,
      messages = messages,
      show_buffer = true,
    })

    return chat:submit()
  end

  self.client:advisor(conversation, function(err, data)
    if err then
      log:error("Advisor Error: %s", err)
      vim.notify(err, vim.log.levels.ERROR)
    end

    table.insert(messages, data.choices[1].message)
    table.insert(messages, {
      role = "user",
      content = "",
    })

    require("codecompanion.strategy.chat").new({
      client = self.client,
      messages = messages,
      show_buffer = true,
    })

    require("codecompanion.utils.ts").goto_heading("prev", 1)
  end)
end

function Advisor:start()
  if self.opts.user_input then
    vim.ui.input({ prompt = string.gsub(self.context.filetype, "^%l", string.upper) .. " Prompt" }, function(input)
      if not input then
        return
      end

      return self:execute(input)
    end)
  else
    return self:execute()
  end
end

return Advisor
