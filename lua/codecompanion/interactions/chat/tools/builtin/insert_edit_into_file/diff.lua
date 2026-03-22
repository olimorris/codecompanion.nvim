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

---Open the diff UI with accept/reject/always_accept keymaps
---@param opts table
local function show_diff(opts)
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

---Show diff and handle approval flow for edits
---@param opts table
---@return any
function M.approve_and_diff(opts)
  local diff_enabled = config.display.diff.enabled == true

  if opts.approved or diff_enabled == false or opts.require_confirmation_after == false then
    return opts.apply_fn()
  end

  local approval_prompt = require("codecompanion.interactions.chat.helpers.approval_prompt")

  local keymaps = config.interactions.shared.keymaps
  approval_prompt.request(opts.chat, {
    title = "View Proposed Edits",
    prompt = opts.title,
    choices = {
      {
        key = keymaps.view_diff.modes.n,
        label = "View",
        resolves = false,
        callback = function()
          show_diff(opts)
        end,
      },
      {
        key = keymaps.always_accept.modes.n,
        label = "Always accept",
        callback = function()
          approvals:always(opts.chat_bufnr, { tool_name = "insert_edit_into_file" })
          opts.apply_fn()
        end,
      },
      {
        key = keymaps.accept_change.modes.n,
        label = "Accept",
        callback = function()
          opts.apply_fn()
        end,
      },
      {
        key = keymaps.reject_change.modes.n,
        label = "Reject",
        callback = function()
          get_rejection_reason(function(reason)
            local msg = fmt('User rejected the edits for `%s`, with the reason "%s"', opts.title, reason)
            opts.output_cb(make_response("error", msg))
          end)
        end,
      },
      {
        key = keymaps.cancel.modes.n,
        label = "Cancel",
        callback = function()
          opts.output_cb(make_response("error", fmt("User cancelled the edits for `%s`", opts.title)))
        end,
      },
    },
  })
end

return M
