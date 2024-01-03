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
  local vars = {
    filetype = self.context.filetype,
  }

  local conversation = {
    model = self.opts.model,
    messages = {},
  }

  local formatted_messages = {}

  -- TODO: Allow for messages to be functions which are executed
  for _, p in ipairs(self.prompts) do
    local content = utils.replace_vars(p.content, p.variables or {}, vars)
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
  self.client:author(conversation, function(err, data)
    if err then
      log:error("Author Error: %s", err)
      vim.notify(err, vim.log.levels.ERROR)
    end

    local response = data.choices[1].message.content

    if string.find(string.lower(response), string.lower("Error")) == 1 then
      return vim.notify(
        "[CodeCompanion.nvim]\nThe OpenAI API could not find a response to your prompt",
        vim.log.levels.ERROR
      )
    end

    vim.bo[self.context.bufnr].modifiable = true
    local output = vim.split(response, "\n")

    if self.context.is_visual and utils.contains(self.opts.modes, "v") then
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

return Author
