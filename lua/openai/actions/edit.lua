local log = require("openai.utils.log")
local schema = require("openai.schema")
local utils = require("openai.utils.util")

---@class openai.ChatEdit
---@field bufnr integer
---@field line1 integer
---@field line2 integer
---@field mode string
---@field client openai.Client
local ChatEdit = {}

---@class openai.ChatEditArgs
---@field line1 integer
---@field line2 integer
---@field mode string
---@field client openai.Client

---@param opts openai.ChatEditArgs
---@return openai.ChatEdit
function ChatEdit.new(opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local self = setmetatable({
    bufnr = bufnr,
    line1 = opts.line1,
    line2 = opts.line2,
    mode = opts.mode,
    client = opts.client,
  }, { __index = ChatEdit })
  return self
end

---@param on_complete nil|fun()
function ChatEdit:start(on_complete)
  local lang = utils.get_language(self.bufnr)

  vim.ui.input({ prompt = string.gsub(lang, "^%l", string.upper) .. " Prompt" }, function(prompt)
    if not prompt then
      return
    end

    local is_visual = self.mode:match("^[vV]")
    local config = schema.static.edit_settings

    local settings = {
      model = config.model.default,
      messages = {
        {
          role = "assistant",
          content = string.format(config.prompts.choices[config.prompts.default], lang),
        },
        {
          role = "user",
          content = prompt,
        },
      },
    }

    if is_visual then
      local lines, _, _, _, _ = utils.get_visual_selection(self.bufnr)

      table.insert(settings.messages, {
        role = "user",
        content = "For context, this is the code:\n" .. table.concat(lines, "\n"),
      })
    end

    vim.bo[self.bufnr].modifiable = false
    self.client:edit(settings, function(err, data)
      if err then
        log:error("ChatEdit Error: %s", err)
      end

      vim.bo[self.bufnr].modifiable = true

      if err then
        vim.notify(err, vim.log.levels.ERROR)
        return
      end

      local replacement = data.choices[1].message.content
      local new_lines = vim.split(replacement, "\n")

      if is_visual then
        local _, start_row, start_col, end_row, end_col = utils.get_visual_selection(self.bufnr)
        log:trace(
          "start_row: %s, start_col: %s, end_row: %s, end_col: %s",
          start_row,
          start_col,
          end_row,
          end_col
        )

        local replacement_lines = vim.split(replacement, "\n")
        vim.api.nvim_buf_set_text(
          self.bufnr,
          start_row - 1,
          start_col - 1,
          end_row - 1,
          end_col,
          replacement_lines
        )
      else
        vim.api.nvim_buf_set_lines(self.bufnr, self.line1 - 1, self.line2, true, new_lines)
      end

      if on_complete then
        on_complete()
      end
    end)
  end)
end

return ChatEdit
