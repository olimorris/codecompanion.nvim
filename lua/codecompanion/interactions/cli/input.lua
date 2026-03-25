local config = require("codecompanion.config")
local input = require("codecompanion.interactions.shared.input")
local log = require("codecompanion.utils.log")

local api = vim.api

local M = {}

---Open the CLI input buffer
---@param opts? { agent?: string, args?: table, initial_content?: string, title?: string }
---@return nil
function M.open(opts)
  opts = opts or {}

  local context_utils = require("codecompanion.utils.context")
  local buffer_context = context_utils.get(api.nvim_get_current_buf(), opts.args)

  input.open({
    title = " " .. (opts.title or config.display.input.title) .. " ",
    initial_content = opts.initial_content,
    on_submit = function(text, submit_opts)
      local cli_module = require("codecompanion.interactions.cli")
      local formatted = cli_module.resolve_editor_context(text, buffer_context)

      local instance = cli_module.last_cli() or cli_module.create({ agent = opts.agent })
      if not instance then
        return log:error("Could not create CLI instance")
      end

      if not instance.ui:is_visible() then
        instance.ui:open()
      end

      instance:send(formatted, { submit = submit_opts.bang })

      if not submit_opts.bang then
        instance:focus()
      end
    end,
  })
end

---Toggle the input buffer
---@param opts? { agent?: string, args?: table, initial_content?: string, title?: string }
---@return nil
function M.toggle(opts)
  if input.is_visible() then
    input.hide()
  else
    M.open(opts)
  end
end

---Hide the input window
---@return nil
function M.hide()
  input.hide()
end

---Check if the input buffer exists (even if hidden)
---@return boolean
function M.is_open()
  return input.is_open()
end

---Check if the input window is currently visible
---@return boolean
function M.is_visible()
  return input.is_visible()
end

return M
