local log = require("codecompanion.utils.log")
local shared_input = require("codecompanion.interactions.shared.input")

local api = vim.api

local M = {}

---Resolve editor context references and format the prompt for CLI
---@param text string
---@param buffer_context CodeCompanion.BufferContext
---@return string
local function format_prompt(text, buffer_context)
  local ec = require("codecompanion.interactions.chat.editor_context").new()
  local message = { content = text }

  local sharing = ec:parse_cli(buffer_context, message)
  local clean_prompt = ec:replace_cli(text)

  if not sharing then
    return clean_prompt
  end

  local parts = {}
  vim.list_extend(parts, sharing)
  table.insert(parts, clean_prompt)
  return table.concat(parts, "\n")
end

---Open the CLI input buffer
---@param opts? { agent?: string, args?: table }
---@return nil
function M.open(opts)
  opts = opts or {}

  local context_utils = require("codecompanion.utils.context")
  local buffer_context = context_utils.get(api.nvim_get_current_buf(), opts.args)

  shared_input.open({
    title = " CodeCompanion CLI ",
    on_submit = function(text)
      local formatted = format_prompt(text, buffer_context)

      local cli_module = require("codecompanion.interactions.cli")
      local instance = cli_module.get_or_create({ agent = opts.agent })
      if not instance then
        return log:error("Could not create CLI instance")
      end

      if not instance.ui:is_visible() then
        instance.ui:open()
      end

      instance:send(formatted)
    end,
  })
end

---Close the input buffer
---@return nil
function M.close()
  shared_input.close()
end

---Check if the input buffer is currently open
---@return boolean
function M.is_open()
  return shared_input.is_open()
end

return M
