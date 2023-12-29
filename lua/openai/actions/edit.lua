---@class openai.ChatEdit
---@field bufnr integer
---@field line1 integer
---@field line2 integer
---@field client openai.Client
local ChatEdit = {}

---@class openai.ChatEditArgs
---@field line1 integer
---@field line2 integer
---@field client openai.Client

---@param opts openai.ChatEditArgs
---@return openai.ChatEdit
function ChatEdit.new(opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local self = setmetatable({
    bufnr = bufnr,
    line1 = opts.line1,
    line2 = opts.line2,
    client = opts.client,
  }, { __index = ChatEdit })
  return self
end

---@param on_complete nil|fun()
function ChatEdit:start(on_complete)
  vim.ui.input({ prompt = "prompt" }, function(prompt)
    if not prompt then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(self.bufnr, self.line1 - 1, self.line2, true)
    local settings = {
      model = "code-davinci-edit-001",
      input = table.concat(lines, "\n"),
      instruction = prompt,
    }

    vim.bo[self.bufnr].modifiable = false
    self.client:edit(settings, function(err, data)
      vim.bo[self.bufnr].modifiable = true
      if err then
        vim.notify(err, vim.log.levels.ERROR)
        return
      end
      local replacement = data.choices[1].text
      local new_lines = vim.split(replacement, "\n")
      -- OpenAI seems to add a blank line at the end
      if new_lines[#new_lines] == "" then
        table.remove(new_lines)
      end
      vim.api.nvim_buf_set_lines(self.bufnr, self.line1 - 1, self.line2, true, new_lines)
      self.line2 = self.line1 + #new_lines - 1
      if on_complete then
        on_complete()
      end
    end)
  end)
end

return ChatEdit
