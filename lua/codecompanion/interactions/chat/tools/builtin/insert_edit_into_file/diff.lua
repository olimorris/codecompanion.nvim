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

---Prompt the user for a rejection reason
---@param callback function
local function get_rejection_reason(callback)
  ui_utils.input({ prompt = "Rejection reason: " }, function(input)
    callback(input or "")
  end)
end

---Open the floating diff view with associated keymaps
---@param opts table
local function open_diff_view(opts)
  local diff_helpers = require("codecompanion.helpers")
  local labels = require("codecompanion.interactions.chat.tools.labels")

  diff_helpers.show_diff({
    chat_bufnr = opts.chat_bufnr,
    diff_id = math.random(10000000),
    ft = opts.ft,
    from_lines = opts.from_lines,
    to_lines = opts.to_lines,
    title = opts.title,
    tool_name = "insert_edit_into_file",
    keymaps = {
      on_always_accept = function()
        if opts.on_done then
          opts.on_done(labels.always_accept)
        end
        approvals:always(opts.chat_bufnr, { tool_name = "insert_edit_into_file" })
      end,
      on_accept = function()
        if opts.on_done then
          opts.on_done(labels.accept)
        end
        opts.apply()
      end,
      on_reject = function()
        if opts.on_done then
          opts.on_done(labels.reject)
        end
        get_rejection_reason(function(reason)
          local msg = fmt('User rejected the edits for `%s`, with the reason "%s"', opts.title, reason)
          opts.output_cb(make_response("error", msg))
        end)
      end,
    },
  })
end

---Build out the choices that users have with respect to the diff and approval flow
---@param opts table
---@return CodeCompanion.Chat.ApprovalChoice[]
local function build_approval_choices(opts)
  local labels = require("codecompanion.interactions.chat.tools.labels")
  local keys = labels.keymaps()

  return {
    {
      keymap = keys.view,
      label = labels.view,
      preview = true,
      callback = function()
        open_diff_view(opts)
      end,
    },
    {
      keymap = keys.always_accept,
      label = labels.always_accept,
      callback = function()
        approvals:always(opts.chat_bufnr, { tool_name = "insert_edit_into_file" })
        opts.apply()
      end,
    },
    {
      keymap = keys.accept,
      label = labels.accept,
      callback = function()
        opts.apply()
      end,
    },
    {
      keymap = keys.reject,
      label = labels.reject,
      callback = function()
        get_rejection_reason(function(reason)
          local msg = fmt('User rejected the edits for `%s`, with the reason "%s"', opts.title, reason)
          opts.output_cb(make_response("error", msg))
        end)
      end,
    },
    {
      keymap = keys.cancel,
      label = labels.cancel,
      callback = function()
        opts.output_cb(make_response("error", fmt("User cancelled the edits for `%s`", opts.title)))
      end,
    },
  }
end

---Allow the user to approve from within the chat buffer
---@param chat CodeCompanion.Chat
---@param opts table
local function approve_in_chat(chat, opts)
  local approval_prompt = require("codecompanion.interactions.chat.helpers.approval_prompt")
  opts.on_done = approval_prompt.request(chat, {
    choices = build_approval_choices(opts),
    prompt = opts.prompt,
    title = opts.title,
  })
end

---Show diff and handle approval flow for edits
---@param opts table
---@return any
function M.review(opts)
  local diff_enabled = config.display.diff.enabled == true

  if opts.approved or diff_enabled == false or opts.require_confirmation_after == false then
    return opts.apply()
  end

  opts.title = fmt("Proposed edits for `%s`:", opts.title)

  local approval_prompt = require("codecompanion.interactions.chat.helpers.approval_prompt")
  approval_prompt.present_diff({
    chat_bufnr = opts.chat_bufnr,
    from_lines = opts.from_lines,
    to_lines = opts.to_lines,
    title = opts.title,
    approve = function(prompt_opts)
      opts.prompt = prompt_opts.prompt
      opts.title = prompt_opts.title
      approve_in_chat(opts.chat, opts)
    end,
    open_diff_view = function()
      open_diff_view(opts)
    end,
  })
end

return M
