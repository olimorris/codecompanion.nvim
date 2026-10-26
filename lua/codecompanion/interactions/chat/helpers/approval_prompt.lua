local config = require("codecompanion.config")
local labels = require("codecompanion.interactions.chat.tools.labels")
local log = require("codecompanion.utils.log")
local markdown = require("codecompanion.utils.markdown")
local tool_calls = require("codecompanion.interactions.chat.ui.tool_calls")
local ui_utils = require("codecompanion.utils.ui")
local utils = require("codecompanion.utils")

local fmt = string.format

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

  table.insert(lines, "Please select an option:")
  for _, choice in ipairs(opts.choices) do
    table.insert(lines, fmt("- `%s` - %s", choice.keymap, choice.label))
  end

  table.insert(lines, "")
  -- table.insert(lines, "---")
  table.insert(lines, "")

  return table.concat(lines, "\n")
end

---Clean up keymaps set for the approval prompt
---@param opts { bufnrs: number[], choices: table }
local function cleanup_keymaps(opts)
  for _, bufnr in ipairs(opts.bufnrs) do
    for _, choice in ipairs(opts.choices) do
      pcall(vim.keymap.del, "n", choice.keymap, { buffer = bufnr })
    end
  end
end

---@class CodeCompanion.Chat.ApprovalChoice
---@field keymap string The keymap to trigger this choice
---@field label string Display label (e.g. "Always accept")
---@field callback function Called when the user selects this choice
---@field preview? boolean When true, the callback fires but the approval prompt stays active (e.g. "View")

---Mark the last line that starts the prompt, so the tool call's details open from it
---@param chat CodeCompanion.Chat
---@param opts { prompt: string, call_id: string }
---@return nil
local function mark_prompt(chat, opts)
  local first_line = vim.split(opts.prompt, "\n", { plain = true })[1]
  local lines = vim.api.nvim_buf_get_lines(chat.bufnr, 0, -1, false)
  for line_number = #lines, 1, -1 do
    if lines[line_number] == first_line then
      return tool_calls.mark(chat, { line_number = line_number, call_id = opts.call_id })
    end
  end
end

---Record the user's choice in the chat buffer
---@param chat CodeCompanion.Chat
---@param choice_label string
---@return nil
local function add_selection(chat, choice_label)
  local is_rejection = labels.is_rejection(choice_label)
  local icons = config.display.chat.icons
  local icon = is_rejection and icons.tool_failure or icons.tool_success
  local status = is_rejection and "failed" or "completed"
  chat:add_buf_message(
    { content = fmt("%sYou selected: %s\n\n---\n", icon, choice_label) },
    { _icon_info = { has_icon = true, status = status } }
  )
end

---@param opts { bufnrs: number[], choices: CodeCompanion.Chat.ApprovalChoice[], is_resolved: fun(): boolean, on_done: fun(choice_label: string) }
---@return nil
local function set_keymaps(opts)
  for _, bufnr in ipairs(opts.bufnrs) do
    for _, choice in ipairs(opts.choices) do
      vim.keymap.set("n", choice.keymap, function()
        if opts.is_resolved() then
          return
        end

        if not choice.preview then
          opts.on_done(choice.label)
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
  end
end

---Request approval from the user via the chat buffer
---@param chat CodeCompanion.Chat
---@param opts { id: string|number, title?: string, prompt?: string, name?: string, call_id?: string, choices: CodeCompanion.Chat.ApprovalChoice[] }
---@return fun(choice_label: string) on_done Callback to finalize the prompt from external code (e.g. diff keymaps)
function M.request(chat, opts)
  local bufnr = chat.bufnr

  utils.fire("ToolApprovalRequested", { bufnr = bufnr, name = opts.name })

  if opts.call_id then
    opts.choices = vim.list_extend({
      labels.build_choice("view", function()
        tool_calls.open(chat, { call_id = opts.call_id })
      end),
    }, opts.choices)
  end

  local content = build_message(opts)
  chat:add_buf_message({ role = config.constants.LLM_ROLE, content = content })
  if opts.call_id and opts.prompt then
    mark_prompt(chat, { prompt = opts.prompt, call_id = opts.call_id })
  end

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
    cleanup_keymaps({ bufnrs = chat:get_bufnrs(), choices = opts.choices })
    add_selection(chat, choice_label)
    utils.fire("ToolApprovalFinished", { bufnr = bufnr, choice = choice_label })
  end

  set_keymaps({
    bufnrs = chat:get_bufnrs(),
    choices = opts.choices,
    is_resolved = function()
      return resolved
    end,
    on_done = on_done,
  })

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
    local prompt = markdown.form_codeblock(diff_text, { ft = "diff" })
    return opts.approve({ title = opts.title, prompt = prompt })
  elseif ui_utils.buf_is_active(opts.chat_bufnr) then
    -- If the chat is active, show the diff in the floating window
    opts.approve({ title = opts.title })
    return opts.open_diff_view()
  else
    -- Otherwise, don't force the diff on the user, just show the approval
    return opts.approve({ title = opts.title })
  end
end

return M
