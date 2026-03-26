local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local ui_utils = require("codecompanion.utils.ui")
local utils = require("codecompanion.utils")

local fmt = string.format

local TOOLS_NS = "CodeCompanion-tools"

local M = {}

---Build the markdown content for the approval prompt
---@param opts table
---@return string
local function build_message(opts)
  local title = opts.title or "Approval Required"
  local lines = { "", "", "---", "**" .. title .. "**", "" }

  if opts.prompt then
    table.insert(lines, opts.prompt)
    table.insert(lines, "")
  end

  for _, choice in ipairs(opts.choices) do
    table.insert(lines, fmt("- `%s` - %s", choice.keymap, choice.label))
  end

  -- table.insert(lines, "")
  table.insert(lines, "---")
  table.insert(lines, "")

  return table.concat(lines, "\n")
end

---Clean up keymaps set for the approval prompt
---@param bufnr number
---@param choices table
local function cleanup_keymaps(bufnr, choices)
  for _, choice in ipairs(choices) do
    pcall(vim.keymap.del, "n", choice.keymap, { buffer = bufnr })
  end
end

---Clear the "Tools processing" indicator
---@param bufnr number
local function clear_processing_msg(bufnr)
  ui_utils.clear_notification(bufnr, { namespace = TOOLS_NS .. "_" .. tostring(bufnr) })
end

---@class CodeCompanion.Chat.ApprovalChoice
---@field keymap string The keymap to trigger this choice
---@field label string Display label (e.g. "Always accept")
---@field callback function Called when the user selects this choice
---@field preview? boolean When true, the callback fires but the approval prompt stays active (e.g. "View")

---Request approval from the user via the chat buffer
---@param chat CodeCompanion.Chat
---@param opts { id: string|number, title?: string, prompt?: string, name?: string, choices: CodeCompanion.Chat.ApprovalChoice[] }
---@return fun(choice_label: string) on_done Callback to finalize the prompt from external code (e.g. diff keymaps)
function M.request(chat, opts)
  local bufnr = chat.bufnr

  clear_processing_msg(bufnr)

  utils.fire("ToolApprovalRequested", { bufnr = bufnr, name = opts.name })

  local content = build_message(opts)
  chat:add_buf_message({ content = content })

  if config.interactions.chat.tools.opts.notify_on_approval and not ui_utils.buf_is_active(bufnr) then
    utils.notify("Tool approval required")
  end

  local resolved = false

  ---Function to call when the user has made a choice
  ---@param choice_label string
  ---@return nil
  local function on_done(choice_label)
    -- Guard against multiple calls
    if resolved then
      return
    end
    resolved = true
    cleanup_keymaps(bufnr, opts.choices)
    utils.fire("ToolApprovalFinished", { bufnr = bufnr, choice = choice_label })
  end

  for _, choice in ipairs(opts.choices) do
    vim.keymap.set("n", choice.keymap, function()
      if resolved then
        return
      end

      if not choice.preview then
        on_done(choice.label)
      end

      log:debug("[approval_prompt] User selected: %s", choice.label)

      choice.callback()
    end, {
      buffer = bufnr,
      desc = choice.label,
      silent = true,
      nowait = true,
    })
  end

  return on_done
end

---Present the diff to the user
---@param opts { chat_bufnr: number, from_lines: string[], to_lines: string[], title: string, approve: fun(prompt_opts: table), open_diff_view: fun() }
function M.present_diff(opts)
  local diff_utils = require("codecompanion.diff.utils")

  local changed_lines = diff_utils.changed_lines(opts.from_lines, opts.to_lines)
  local threshold = config.display.diff.threshold_for_chat
  local threshold_met = threshold and threshold > 0 and changed_lines > 0 and changed_lines <= threshold

  if threshold_met then
    -- Show small diffs in the chat buffer
    local diff_text = diff_utils.unified(opts.from_lines, opts.to_lines)
    local prompt = fmt("`````diff\n%s\n`````", diff_text)
    return opts.approve({ title = opts.title, prompt = prompt })
  elseif ui_utils.buf_is_active(opts.chat_bufnr) then
    -- If the chat is active, show the diff in the floating window
    opts.approve({ title = opts.title, prompt = opts.title })
    return opts.open_diff_view()
  else
    -- Otherwise, don't force the diff on the user, just show the approval
    return opts.approve({ title = opts.title, prompt = opts.title })
  end
end

return M
