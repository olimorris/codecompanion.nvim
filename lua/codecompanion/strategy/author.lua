local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils.util")

---@class CodeCompanion.Author
---@field context table
---@field client CodeCompanion.Client
---@field opts table
---@field prompts table
local Author = {}

---@class CodeCompanion.AuthorArgs
---@field context table
---@field client CodeCompanion.Client
---@field opts table
---@field prompts table

---@param opts CodeCompanion.AuthorArgs
---@return CodeCompanion.Author
function Author.new(opts)
  log:trace("Initiating Author")

  local self = setmetatable({
    context = opts.context,
    client = opts.client,
    opts = opts.opts,
    prompts = opts.prompts,
  }, { __index = Author })
  return self
end

---@param user_input string|nil
function Author:execute(user_input)
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
      content = "For context, this is the code I will ask you to help me with:\n"
        .. table.concat(self.context.lines, "\n"),
    })
  end

  vim.bo[self.context.bufnr].modifiable = false
  self.client:author(conversation, function(err, data)
    if err then
      vim.bo[self.context.bufnr].modifiable = true
      log:error("Author Error: %s", err)
      vim.notify(err, vim.log.levels.ERROR)
    end

    local response = data.choices[1].message.content

    if string.find(response, "^%[Error%]") == 1 then
      vim.bo[self.context.bufnr].modifiable = true
      return require("codecompanion.utils.ui").display(
        config.options.display,
        response,
        conversation.messages,
        self.client
      )
    end

    vim.bo[self.context.bufnr].modifiable = true
    local output = vim.split(response, "\n")

    if self.context.is_visual and (self.opts.modes and utils.contains(self.opts.modes, "v")) then
      vim.api.nvim_buf_set_text(
        self.context.bufnr,
        self.context.start_line - 1,
        self.context.start_col - 1,
        self.context.end_line - 1,
        self.context.end_col,
        output
      )
    else
      vim.api.nvim_buf_set_lines(
        self.context.bufnr,
        self.context.cursor_pos[1] - 1,
        self.context.cursor_pos[1] - 1,
        true,
        output
      )
    end
  end)
end

function Author:start()
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

return Author
