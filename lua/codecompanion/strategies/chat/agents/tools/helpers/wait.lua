local config = require("codecompanion.config")
local utils = require("codecompanion.utils")
local api = vim.api

local M = {}

---Wait for user decision on specific events
---@param id string|number Unique identifier for the decision context
---@param events table Name of events to wait for. First one is considered "accept"
---@param callback function Callback to execute when decision is made
---@param opts? table Optional configuration
function M.for_decision(id, events, callback, opts)
  opts = opts or {}

  -- Auto-approve if in auto mode
  -- Generally, most tools will avoid us reaching this point, but it's a good fallback
  if vim.g.codecompanion_auto_tool_mode then
    return callback({ accepted = true })
  end

  local aug = api.nvim_create_augroup("codecompanion_wait_" .. tostring(id), { clear = true })

  if opts.notify then
    utils.notify(opts.notify or "Waiting for user decision...")
  end

  api.nvim_create_autocmd("User", {
    group = aug,
    pattern = events,
    callback = function(event)
      local event_data = event.data or {}

      if id ~= event_data.id then
        return
      end

      local accepted = (event.match == events[1])
      api.nvim_clear_autocmds({ group = aug })
      callback({
        accepted = accepted,
        event = event.match,
        data = event_data,
      })
    end,
  })

  opts.timeout = opts.timeout or config.strategies.chat.tools.wait_timeout or 30000

  vim.defer_fn(function()
    api.nvim_clear_autocmds({ group = aug })
    callback({
      accepted = false,
      timeout = true,
    })
  end, opts.timeout)
end

return M
