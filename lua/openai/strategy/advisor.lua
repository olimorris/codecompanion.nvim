local config = require("openai.config")
local log = require("openai.utils.log")
local utils = require("openai.utils.util")

---@class openai.Advisor
---@field context table
---@field client openai.Client
---@field opts table
---@field prompts table
local Advisor = {}

---@class openai.AuthorArgs
---@field context table
---@field client openai.Client
---@field opts table
---@field prompts table

---@param opts openai.AuthorArgs
---@return openai.Advisor
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
  local vars = {
    filetype = self.context.filetype,
  }

  local conversation = {
    model = self.opts.model,
    messages = {},
  }

  local formatted_messages = {}

  for _, p in ipairs(self.prompts) do
    local content
    if type(p.content) == "function" then
      content = p.content(self.context)
    else
      content = utils.replace_vars(p.content, p.variables or {}, vars)
    end

    table.insert(formatted_messages, {
      role = p.role,
      content = content,
    })
  end

  -- Add the user prompt last
  if self.opts.user_input and user_input then
    table.insert(formatted_messages, {
      role = "user",
      content = user_input,
    })
  end

  conversation.messages = formatted_messages

  if
    self.opts.send_visual_selection
    and (self.context.is_visual and utils.contains(self.opts.modes, "v"))
  then
    table.insert(conversation.messages, 2, {
      role = "user",
      content = "For context, this is the code I will ask you to help me with:\n"
        .. table.concat(self.context.lines, "\n"),
    })
  end

  vim.bo[self.context.bufnr].modifiable = false
  self.client:advisor(conversation, function(err, data)
    if err then
      log:error("Advisor Error: %s", err)
      vim.notify(err, vim.log.levels.ERROR)
    end

    local response = data.choices[1].message.content

    return require("openai.utils.ui").display(config.config.display, response)
  end)
end

function Advisor:start()
  if self.context.is_normal and not utils.contains(self.opts.modes, "n") then
    return vim.notify(
      "[CodeCompanion.nvim]\nThis action is not enabled for Normal mode",
      vim.log.levels.WARN
    )
  end

  if self.context.is_visual and not utils.contains(self.opts.modes, "v") then
    return vim.notify(
      "[CodeCompanion.nvim]\nThis action is not enabled for Visual mode",
      vim.log.levels.WARN
    )
  end

  if self.opts.user_input then
    vim.ui.input(
      { prompt = string.gsub(self.context.filetype, "^%l", string.upper) .. " Prompt" },
      function(input)
        if not input then
          return
        end

        return self:execute(input)
      end
    )
  else
    return self:execute()
  end
end

return Advisor
