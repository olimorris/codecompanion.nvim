local config = require("codecompanion.config")
local keymaps = require("codecompanion.utils.keymaps")
local ui_utils = require("codecompanion.utils.ui")
local utils = require("codecompanion.utils")

local api = vim.api
local fmt = string.format

local CONSTANTS = {
  MAX_OPTIONS = 9,

  YES_KEY = "g1",
  NO_KEY = "g2",
  SKIP_KEY = "gs",
  CUSTOM_ANSWER_KEY = "gc",

  DESC = "CodeCompanion question",
}

CONSTANTS.DESC_CUSTOM_ANSWER = CONSTANTS.DESC .. ": write a custom answer"
CONSTANTS.DESC_SKIP = CONSTANTS.DESC .. ": skip this question"

---@class CodeCompanion.Chat.QuestionPrompt
local M = {}

---@param option table
---@return string
local function format_label(option)
  local label = option.label
  if option.recommended then
    label = label .. " (recommended)"
  end
  if option.description then
    label = label .. " - " .. option.description
  end
  return label
end

---Build the line that shows which option is being answered in a multi-select question
---@param label string
---@return string
local function include_prompt(label)
  return fmt("Include '%s'?", label)
end

---Build the markdown lines for a question
---@param opts { question: table, index: number, total: number }
---@return string[]
local function build_lines(opts)
  local question = opts.question
  local options = question.options or {}

  local header = fmt("**Question %d of %d**", opts.index, opts.total)
  if question.multiSelect then
    header = header .. " (select multiple)"
  end

  local lines = { "", "", "---", header, "", question.question, "" }

  if #options == 0 then
    table.insert(lines, fmt("- `%s` - Write your answer", CONSTANTS.CUSTOM_ANSWER_KEY))
    table.insert(lines, fmt("- `%s` - Skip this question", CONSTANTS.SKIP_KEY))
    table.insert(lines, "")
    return lines
  end

  if question.multiSelect then
    for _, option in ipairs(options) do
      table.insert(lines, "- " .. format_label(option))
    end
    table.insert(lines, "")
    table.insert(
      lines,
      fmt("`%s` Yes · `%s` No · `%s` Skip question", CONSTANTS.YES_KEY, CONSTANTS.NO_KEY, CONSTANTS.SKIP_KEY)
    )
    table.insert(lines, "")

    -- NOTE: The line must stay last: its line number is tracked so it can be updated in place
    table.insert(lines, include_prompt(options[1].label))
    return lines
  end

  table.insert(lines, "Please select an option:")
  for i = 1, math.min(#options, CONSTANTS.MAX_OPTIONS) do
    table.insert(lines, fmt("- `g%d` - %s", i, format_label(options[i])))
  end
  table.insert(lines, fmt("- `%s` - Write a custom answer", CONSTANTS.CUSTOM_ANSWER_KEY))
  table.insert(lines, fmt("- `%s` - Skip this question", CONSTANTS.SKIP_KEY))
  table.insert(lines, "")
  return lines
end

---Add the answer summary to the chat buffer
---@param chat CodeCompanion.Chat
---@param answer string|nil
local function add_summary(chat, answer)
  local icons = config.display.chat.icons
  if answer then
    return chat:add_buf_message(
      { content = fmt("%sYou answered: %s\n\n---\n", icons.tool_success, answer) },
      { _icon_info = { has_icon = true, status = "completed" } }
    )
  end

  chat:add_buf_message(
    { content = fmt("%sYou skipped this question\n\n---\n", icons.tool_failure) },
    { _icon_info = { has_icon = true, status = "failed" } }
  )
end

---Bind keymaps for a multi-select question, advancing through each option in turn
---@param prompt { chat: CodeCompanion.Chat, options: table[], include_line: number|nil, bind: fun(lhs: string, callback: function, desc: string), finish: fun(answer: string|nil), skip: function }
local function bind_multi_select(prompt)
  local selected = {}
  local option_index = 1

  -- Ensure the summary message is on its own line
  local function clear_include_line()
    if prompt.include_line then
      prompt.chat:update_buf_line(prompt.include_line, "")
    end
  end

  local function advance()
    option_index = option_index + 1
    if option_index > #prompt.options then
      clear_include_line()
      return prompt.finish(#selected > 0 and table.concat(selected, ", ") or nil)
    end
    if prompt.include_line then
      prompt.chat:update_buf_line(prompt.include_line, include_prompt(prompt.options[option_index].label))
    end
  end

  prompt.bind(CONSTANTS.YES_KEY, function()
    table.insert(selected, prompt.options[option_index].label)
    advance()
  end, CONSTANTS.DESC .. ": include this option")
  prompt.bind(CONSTANTS.NO_KEY, advance, CONSTANTS.DESC .. ": exclude this option")
  prompt.bind(CONSTANTS.SKIP_KEY, function()
    clear_include_line()
    prompt.skip()
  end, CONSTANTS.DESC_SKIP)
end

---Bind keymaps for a single-select question
---@param prompt { options: table[], bind: fun(lhs: string, callback: function, desc: string), finish: fun(answer: string|nil), custom_answer: function }
local function bind_single_select(prompt)
  for i = 1, math.min(#prompt.options, CONSTANTS.MAX_OPTIONS) do
    prompt.bind("g" .. i, function()
      prompt.finish(prompt.options[i].label)
    end, CONSTANTS.DESC .. ": " .. prompt.options[i].label)
  end
  prompt.bind(CONSTANTS.CUSTOM_ANSWER_KEY, prompt.custom_answer, CONSTANTS.DESC_CUSTOM_ANSWER)
end

---Present a question in the chat buffer and resolve the answer through keymaps
---@param chat CodeCompanion.Chat
---@param opts { question: table, index: number, total: number, callback: fun(answer: string|nil) }
---@return nil
function M.ask(chat, opts)
  local bufnr = chat.bufnr
  if not api.nvim_buf_is_valid(bufnr) then
    return opts.callback(nil)
  end

  local options = opts.question.options or {}
  local last_line = chat:add_buf_message({
    role = config.constants.LLM_ROLE,
    content = table.concat(build_lines(opts), "\n"),
  })

  if config.interactions.chat.tools.opts.notify_on_approval and not ui_utils.buf_is_active(bufnr) then
    utils.notify("The LLM has a question for you")
  end

  local overrides = keymaps.Override.new(bufnr)
  local resolved = false

  local function bind(lhs, callback, desc)
    overrides:set(lhs, callback, { desc = desc })
  end

  ---@param answer string|nil
  local function finish(answer)
    if resolved then
      return
    end
    resolved = true
    overrides:restore()
    add_summary(chat, answer)
    opts.callback(answer)
  end

  local function custom_answer()
    vim.ui.input({ prompt = "Answer: " }, function(input)
      -- A cancelled input leaves the question active so the user can still press another key
      if input and input ~= "" then
        finish(input)
      end
    end)
  end

  local function skip()
    finish(nil)
  end

  if #options == 0 then
    bind(CONSTANTS.SKIP_KEY, skip, CONSTANTS.DESC_SKIP)
    bind(CONSTANTS.CUSTOM_ANSWER_KEY, custom_answer, CONSTANTS.DESC_CUSTOM_ANSWER)
    return
  end
  if opts.question.multiSelect then
    return bind_multi_select({
      chat = chat,
      options = options,
      include_line = last_line,
      bind = bind,
      finish = finish,
      skip = skip,
    })
  end
  bind(CONSTANTS.SKIP_KEY, skip, CONSTANTS.DESC_SKIP)
  bind_single_select({ options = options, bind = bind, finish = finish, custom_answer = custom_answer })
end

return M
