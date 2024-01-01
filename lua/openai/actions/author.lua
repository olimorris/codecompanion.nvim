local log = require("openai.utils.log")
local utils = require("openai.utils.util")

---@class openai.Author
---@field context table
---@field client openai.Client
---@field opts table
---@field prompts table
local Author = {}

---@class openai.AuthorArgs
---@field context table
---@field client openai.Client
---@field opts table
---@field prompts table

---@param opts openai.AuthorArgs
---@return openai.Author
function Author.new(opts)
  log:trace("Initiating Author")

  local self = setmetatable({
    context = opts.context,
    client = opts.client,
    opts = opts.opts,
    prompts = opts.prompts,
    messages = {},
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

  -- Add the prompts from the user's config
  -- TODO: Allow for function messages
  for _, p in ipairs(self.prompts) do
    local msg = utils.replace_vars(p.message, p.variables or {}, vars)
    table.insert(formatted_messages, {
      role = p.role,
      content = msg,
    })
  end

  -- -- Add the user prompt last
  if self.opts.user_input then
    table.insert(formatted_messages, {
      role = "user",
      content = user_input,
    })
  end

  conversation.messages = formatted_messages

  if self.context.is_visual then
    table.insert(conversation.messages, 2, {
      role = "user",
      content = "For context, this is the code I will ask you to help me with:\n"
        .. table.concat(self.context.lines, "\n"),
    })
  end

  vim.bo[self.context.bufnr].modifiable = false
  self.client:assistant(conversation, function(err, data)
    if err then
      log:error("Author Error: %s", err)
    end

    vim.bo[self.context.bufnr].modifiable = true

    if err then
      vim.notify(err, vim.log.levels.ERROR)
      return
    end

    local new_lines = vim.split(data.choices[1].message.content, "\n")

    if self.context.is_visual then
      vim.api.nvim_buf_set_text(
        self.context.bufnr,
        self.context.start_line - 1,
        self.context.start_col - 1,
        self.context.end_line - 1,
        self.context.end_col,
        new_lines
      )
    else
      vim.api.nvim_buf_set_lines(
        self.context.bufnr,
        self.context.cursor_pos[1] - 1,
        self.context.cursor_pos[1] - 1,
        true,
        new_lines
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
