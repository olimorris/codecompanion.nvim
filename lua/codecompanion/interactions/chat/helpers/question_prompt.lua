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

---Each question gets its own id so the asked and answered events can be paired
local question_id = 0

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
---@param opts? { answer?: string }
local function add_summary(chat, opts)
  opts = opts or {}
  local icons = config.display.chat.icons
  if opts.answer then
    return chat:add_buf_message(
      { content = fmt("%sYou answered: %s\n\n---\n", icons.tool_success, opts.answer) },
      { _icon_info = { has_icon = true, status = "completed" } }
    )
  end

  chat:add_buf_message(
    { content = fmt("%sYou skipped this question\n\n---\n", icons.tool_failure) },
    { _icon_info = { has_icon = true, status = "failed" } }
  )
end

---Bind keymaps for a multi-select question, advancing through each option in turn
---@param prompt { chat: CodeCompanion.Chat, options: table[], include_line: number|nil, bind: fun(lhs: string, callback: function, desc: string), finish: fun(result?: { answer?: string, selected?: string[] }), skip: function, cancel: function }
---@return fun() cancel
local function bind_multi_select(prompt)
  local selected = {}
  local option_index = 1

  -- Ensure the summary message is on its own line
  local function clear_include_line()
    if prompt.include_line then
      prompt.chat:update_buf_line({ line_number = prompt.include_line, content = "" })
    end
  end

  local function advance()
    option_index = option_index + 1
    if option_index > #prompt.options then
      clear_include_line()
      if #selected == 0 then
        return prompt.finish({ answer = nil })
      end
      return prompt.finish({
        answer = table.concat(selected, ", "),
        selected = vim.list_slice(selected),
      })
    end
    if prompt.include_line then
      prompt.chat:update_buf_line({
        line_number = prompt.include_line,
        content = include_prompt(prompt.options[option_index].label),
      })
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

  return function()
    clear_include_line()
    prompt.cancel()
  end
end

---Bind keymaps for a single-select question
---@param prompt { options: table[], bind: fun(lhs: string, callback: function, desc: string), finish: fun(result?: { answer?: string, selected?: string[] }), custom_answer: function }
local function bind_single_select(prompt)
  for i = 1, math.min(#prompt.options, CONSTANTS.MAX_OPTIONS) do
    prompt.bind("g" .. i, function()
      prompt.finish({ answer = prompt.options[i].label })
    end, CONSTANTS.DESC .. ": " .. prompt.options[i].label)
  end
  prompt.bind(CONSTANTS.CUSTOM_ANSWER_KEY, prompt.custom_answer, CONSTANTS.DESC_CUSTOM_ANSWER)
end

---Dismiss a custom-answer prompt that is still waiting for input
---@param session { custom_input_active: boolean }
local function close_custom_input(session)
  if not session.custom_input_active then
    return
  end
  session.custom_input_active = false
  vim.api.nvim_input("<Esc>")
end

---Restore the chat keymaps and close any open custom-answer input
---@param session table
local function cancel_question(session)
  if session.resolved then
    return
  end
  session.resolved = true
  session.overrides:restore()
  close_custom_input(session)
end

---Record the answer and invoke the question callback
---@param session table
---@param opts? { answer?: string, selected?: string[] }
local function complete_answer(session, opts)
  opts = opts or {}
  if session.resolved then
    return
  end
  -- A submitted answer is already closing the input, so cancellation must not send Esc
  session.custom_input_active = false
  cancel_question(session)
  local answer = opts.answer
  add_summary(session.chat, { answer = answer })
  utils.fire("ToolQuestionAnswered", {
    answer = answer,
    bufnr = session.bufnr,
    header = session.header,
    id = session.id,
    skipped = answer == nil,
  })
  session.callback({ answer = answer, selected = opts.selected })
end

---Open the custom-answer input and finish when the user submits text
---@param session table
local function ask_custom_answer(session)
  session.custom_input_active = true
  vim.ui.input({ prompt = "Answer: " }, function(input)
    session.custom_input_active = false
    if session.resolved then
      return
    end
    -- A cancelled input leaves the question active so the user can still press another key
    if input and input ~= "" then
      complete_answer(session, { answer = input })
    end
  end)
end

---Bind the keymaps that resolve one question
---@param session table
---@param opts { options: table[], include_line: number|nil, multi_select: boolean }
---@return fun()|nil cancel
local function bind_question_keys(session, opts)
  opts = opts or {}
  local function bind(lhs, callback, desc)
    session.overrides:set(lhs, callback, { desc = desc })
  end
  local function finish(result)
    complete_answer(session, result)
  end
  local function skip()
    finish({})
  end

  local options = opts.options or {}
  if #options == 0 then
    bind(CONSTANTS.SKIP_KEY, skip, CONSTANTS.DESC_SKIP)
    bind(CONSTANTS.CUSTOM_ANSWER_KEY, function()
      ask_custom_answer(session)
    end, CONSTANTS.DESC_CUSTOM_ANSWER)
    return
  end

  if opts.multi_select then
    return bind_multi_select({
      chat = session.chat,
      options = options,
      include_line = opts.include_line,
      bind = bind,
      finish = finish,
      skip = skip,
      cancel = function()
        cancel_question(session)
      end,
    })
  end

  bind(CONSTANTS.SKIP_KEY, skip, CONSTANTS.DESC_SKIP)
  bind_single_select({
    options = options,
    bind = bind,
    finish = finish,
    custom_answer = function()
      ask_custom_answer(session)
    end,
  })
end

---Post the question and remember the session used to resolve it
---@param chat CodeCompanion.Chat
---@param opts { question: table, index: number, total: number, callback: function }
---@return table session
---@return number|nil last_line
local function begin_question(chat, opts)
  opts = opts or {}
  question_id = question_id + 1
  local bufnr = chat.bufnr
  local session = {
    bufnr = bufnr,
    callback = opts.callback,
    chat = chat,
    custom_input_active = false,
    header = opts.question.header,
    id = question_id,
    overrides = keymaps.Override.new(bufnr),
    resolved = false,
  }

  local last_line = chat:add_buf_message({
    role = config.constants.LLM_ROLE,
    content = table.concat(build_lines(opts), "\n"),
  })

  utils.fire("ToolQuestionAsked", {
    bufnr = bufnr,
    header = opts.question.header,
    id = session.id,
    index = opts.index,
    question = opts.question.question,
    total = opts.total,
  })

  if config.interactions.chat.tools.opts.notify_on_approval and not ui_utils.buf_is_active(bufnr) then
    utils.notify("The LLM has a question for you")
  end

  return session, last_line
end

---Present a question in the chat buffer and resolve the answer through keymaps
---@param chat CodeCompanion.Chat
---@param opts { question: table, index: number, total: number, callback: fun(result: { answer: string|nil, selected?: string[] }) }
---@return fun() cancel
function M.ask(chat, opts)
  opts = opts or {}
  if not api.nvim_buf_is_valid(chat.bufnr) then
    opts.callback({ answer = nil })
    return function() end
  end

  local session, last_line = begin_question(chat, opts)
  local cancel_keys = bind_question_keys(session, {
    include_line = last_line,
    multi_select = opts.question.multiSelect == true,
    options = opts.question.options or {},
  })

  return function()
    if cancel_keys then
      cancel_keys()
      return
    end
    cancel_question(session)
  end
end

return M
