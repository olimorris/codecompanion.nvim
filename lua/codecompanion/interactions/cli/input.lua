local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local shared_input = require("codecompanion.interactions.shared.input")

local api = vim.api

local M = {}

---Open the CLI input buffer
---@param opts? { agent?: string, args?: table, initial_content?: string, title?: string }
---@return nil
function M.open(opts)
  opts = opts or {}

  local context_utils = require("codecompanion.utils.context")
  local buffer_context = context_utils.get(api.nvim_get_current_buf(), opts.args)

  shared_input.open({
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
