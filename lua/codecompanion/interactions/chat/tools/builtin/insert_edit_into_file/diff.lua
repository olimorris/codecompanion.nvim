--[[Diff display and approval flow for insert_edit_into_file]]

local approvals = require("codecompanion.interactions.chat.tools.approvals")
local config = require("codecompanion.config")
local ui_utils = require("codecompanion.utils.ui")

local fmt = string.format

local M = {}

---Create response for output_cb
---@param status "success"|"error"
---@param msg string
---@return table
local function make_response(status, msg)
  return { status = status, data = msg }
end

---Prompt user for rejection reason
---@param callback function
local function get_rejection_reason(callback)
  ui_utils.input({ prompt = "Rejection reason" }, function(input)
    callback(input or "")
  end)
end

---Show diff and handle approval flow for edits
---@param opts table
---@return any
function M.approve_and_diff(opts)
  local diff_enabled = config.display.diff.enabled == true

  if opts.approved or diff_enabled == false or opts.require_confirmation_after == false then
    return opts.apply_fn()
  end

  local diff_id = math.random(10000000)
  local diff_helpers = require("codecompanion.helpers")

  diff_helpers.show_diff({
    chat_bufnr = opts.chat_bufnr,
    diff_id = diff_id,
    ft = opts.ft,
    from_lines = opts.from_lines,
    to_lines = opts.to_lines,
    title = opts.title,
    tool_name = "insert_edit_into_file",
    keymaps = {
      on_always_accept = function()
        approvals:always(opts.chat_bufnr, { tool_name = "insert_edit_into_file" })
      end,
      on_accept = function()
        opts.apply_fn()
      end,
      on_reject = function()
        get_rejection_reason(function(reason)
          local msg = fmt('User rejected the edits for `%s`, with the reason "%s"', opts.title, reason)
          opts.output_cb(make_response("error", msg))
        end)
      end,
    },
  })
end

return M
