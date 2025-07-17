local config = require("codecompanion.config")
local ui = require("codecompanion.utils.ui")
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

  local aug = api.nvim_create_augroup("codecompanion.agent.tools.wait_" .. tostring(id), { clear = true })

  -- Show waiting indicator in the chat buffer
  local chat_extmark_id = nil
  if opts.chat_bufnr then
    chat_extmark_id = M.show_waiting_indicator(opts.chat_bufnr, opts)
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

      if chat_extmark_id and opts.chat_bufnr then
        M.clear_waiting_indicator(opts.chat_bufnr)
      end

      api.nvim_clear_autocmds({ group = aug })
      callback({
        accepted = accepted,
        event = event.match,
        data = event_data,
      })
    end,
  })

  if opts.notify then
    utils.notify(opts.notify or "Waiting for user decision ...")
  end

  opts.timeout = opts.timeout or config.strategies.chat.tools.opts.wait_timeout or 30000
  vim.defer_fn(function()
    if chat_extmark_id and opts.chat_bufnr then
      M.clear_waiting_indicator(opts.chat_bufnr)
    end

    api.nvim_clear_autocmds({ group = aug })
    callback({
      accepted = false,
      timeout = true,
    })
  end, opts.timeout)
end

---Show a waiting indicator in the chat buffer
---@param bufnr number The buffer number to show the indicator in
---@param opts table Options for the indicator
---@return number The extmark ID for cleanup
function M.show_waiting_indicator(bufnr, opts)
  opts = opts or {}

  local notify = opts.notify or "Waiting for user decision ..."
  local sub_text = opts.sub_text

  return ui.show_buffer_notification(bufnr, {
    namespace = "codecompanion_waiting_" .. tostring(bufnr),
    footer = true,
    text = notify,
    sub_text = sub_text,
    main_hl = "CodeCompanionChatWarn",
    sub_hl = "CodeCompanionChatSubtext",
  })
end

---Clear the waiting indicator
---@param bufnr number The buffer number to clear the indicator from
---@return nil
function M.clear_waiting_indicator(bufnr)
  ui.clear_notification(bufnr, { namespace = "codecompanion_waiting_" .. tostring(bufnr) })
end

return M
