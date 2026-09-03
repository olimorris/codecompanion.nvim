local config = require("codecompanion.config")
local helpers = require("codecompanion.adapters.acp.helpers")
local jsonrpc = require("codecompanion.utils.jsonrpc")
local question_prompt = require("codecompanion.interactions.chat.helpers.question_prompt")

local ASK_USER_QUESTION_METHODS = {
  ["x.ai/ask_user_question"] = true,
  ["_x.ai/ask_user_question"] = true,
}

local EXIT_PLAN_MODE_METHODS = {
  ["x.ai/exit_plan_mode"] = true,
  ["_x.ai/exit_plan_mode"] = true,
}

---Unwrap an xAI extension request when it uses the ACP extension envelope
---@param params table
---@return table
local function unwrap_params(params)
  if type(params.params) == "table" then
    return params.params
  end
  return params
end

---Recover selected labels from the comma-separated multi-select answer
---@param options table[]
---@param answer string
---@param start_index? number
---@return string[]|nil
local function recover_selected_labels(options, answer, start_index)
  if answer == "" then
    return {}
  end
  for index = start_index or 1, #options do
    local label = options[index].label
    if type(label) == "string" then
      if answer == label then
        return { label }
      end
      local prefix = label .. ", "
      if answer:sub(1, #prefix) == prefix then
        local remaining = recover_selected_labels(options, answer:sub(#prefix + 1), index + 1)
        if remaining then
          table.insert(remaining, 1, label)
          return remaining
        end
      end
    end
  end
end

---Normalize one answer for Grok's extension response
---@param question table
---@param answer string
---@return string[] labels
---@return table|nil annotation
local function normalize_answer(question, answer)
  local options = type(question.options) == "table" and question.options or {}
  local labels
  if question.multiSelect == true then
    labels = recover_selected_labels(options, answer)
  else
    for _, option in ipairs(options) do
      if option.label == answer then
        labels = { answer }
        local preview = type(option.preview) == "string" and vim.trim(option.preview) or ""
        return labels, preview ~= "" and { preview = preview } or nil
      end
    end
  end

  if labels then
    return labels
  end
  return { "Other" }, { notes = answer }
end

---Convert a Grok question into CodeCompanion's question prompt shape
---@param question table
---@return table
local function question_for_chat(question)
  local options = {}
  for _, option in ipairs(type(question.options) == "table" and question.options or {}) do
    if type(option) == "table" and type(option.label) == "string" then
      table.insert(options, {
        label = option.label,
        description = type(option.description) == "string" and option.description or nil,
      })
    end
  end
  return {
    header = "Grok Build",
    question = question.question,
    multiSelect = question.multiSelect == true,
    options = options,
  }
end

---Check the questions before opening an interactive prompt
---@param questions any
---@return boolean
local function valid_questions(questions)
  if type(questions) ~= "table" or #questions == 0 then
    return false
  end
  for _, question in ipairs(questions) do
    if type(question) ~= "table" or type(question.question) ~= "string" then
      return false
    end
  end
  return true
end

---Finish a Grok question request after the final answer
---@param request CodeCompanion.ACP.ClientRequest
---@param state table
local function finish_questions(request, state)
  local response = { outcome = "accepted", answers = state.answers }
  if not vim.tbl_isempty(state.annotations) then
    response.annotations = state.annotations
  end
  request.respond(response)
end

local ask_next_question

---Present the next question in a Grok request
---@param request CodeCompanion.ACP.ClientRequest
---@param state table
ask_next_question = function(request, state)
  state.index = state.index + 1
  if state.index > #state.questions then
    return finish_questions(request, state)
  end

  local question = state.questions[state.index]
  state.cancel_current = question_prompt.ask(request.chat, {
    question = question_for_chat(question),
    index = state.index,
    total = #state.questions,
    callback = function(answer)
      state.cancel_current = nil
      if state.cancelled then
        return
      end
      if answer then
        local labels, annotation = normalize_answer(question, answer)
        state.answers[question.question] = labels
        if annotation then
          state.annotations[question.question] = annotation
        end
      end
      ask_next_question(request, state)
    end,
  })
end

---Present Grok's questions and return the answers over ACP
---@param request CodeCompanion.ACP.ClientRequest
---@return boolean
local function handle_ask_user_question(request)
  local questions = unwrap_params(request.params).questions
  if not valid_questions(questions) then
    request.reject("Invalid Grok question request", jsonrpc.errors.INVALID_PARAMS)
    return true
  elseif not request.chat then
    request.respond({ outcome = "cancelled" })
    return true
  end

  local state = { answers = vim.empty_dict(), annotations = {}, cancelled = false, index = 0 }
  state.questions = questions
  request.on_cancel(function()
    state.cancelled = true
    if state.cancel_current then
      state.cancel_current()
    end
    request.respond({ outcome = "cancelled" })
  end)
  ask_next_question(request, state)
  return true
end

---Respond to the user's Grok plan decision
---@param request CodeCompanion.ACP.ClientRequest
---@param state table
---@param answer string|nil
local function respond_to_plan_choice(request, state, answer)
  if state.cancelled then
    return
  end
  if answer == "Approve" then
    return request.respond({ outcome = "approved" })
  elseif answer == "Request changes" then
    return vim.ui.input({ prompt = "Plan feedback: " }, function(feedback)
      if not state.cancelled then
        local response = { outcome = "cancelled" }
        if feedback and vim.trim(feedback) ~= "" then
          response.feedback = feedback
        end
        request.respond(response)
      end
    end)
  elseif answer and answer ~= "Abandon" then
    return request.respond({ outcome = "cancelled", feedback = answer })
  end
  request.respond({ outcome = "abandoned" })
end

---Present Grok's plan and return the user's decision over ACP
---@param request CodeCompanion.ACP.ClientRequest
---@return boolean
local function handle_exit_plan_mode(request)
  if not request.chat then
    request.respond({ outcome = "abandoned" })
    return true
  end

  local params = unwrap_params(request.params)
  local plan = type(params.planContent) == "string" and vim.trim(params.planContent) or ""
  if plan ~= "" then
    request.chat:add_buf_message({
      role = config.constants.LLM_ROLE,
      content = "**Grok Build proposed plan**\n\n" .. plan,
    }, { type = request.chat.MESSAGE_TYPES.LLM_MESSAGE })
  end

  local state = { cancelled = false }
  request.on_cancel(function()
    state.cancelled = true
    if state.cancel_question then
      state.cancel_question()
    end
    request.respond({ outcome = "abandoned" })
  end)

  state.cancel_question = question_prompt.ask(request.chat, {
    question = {
      header = "Plan review",
      question = "What should Grok Build do with this plan?",
      options = {
        { label = "Approve", description = "Continue and implement the plan", recommended = true },
        { label = "Request changes", description = "Revise the plan before implementation" },
        { label = "Abandon", description = "Stop without implementing the plan" },
      },
    },
    index = 1,
    total = 1,
    callback = function(answer)
      state.cancel_question = nil
      respond_to_plan_choice(request, state, answer)
    end,
  })
  return true
end

---Handle Grok Build's agent-to-client ACP extensions
---@param _ CodeCompanion.ACPAdapter
---@param request CodeCompanion.ACP.ClientRequest
---@return boolean
local function handle_acp_request(_, request)
  if ASK_USER_QUESTION_METHODS[request.method] then
    return handle_ask_user_question(request)
  elseif EXIT_PLAN_MODE_METHODS[request.method] then
    return handle_exit_plan_mode(request)
  end
  return false
end

---@class CodeCompanion.ACPAdapter.Grok: CodeCompanion.ACPAdapter
return {
  name = "grok",
  formatted_name = "Grok Build",
  type = "acp",
  roles = {
    llm = "assistant",
    user = "user",
  },
  commands = {
    default = {
      "grok",
      "agent",
      "stdio",
    },
  },
  defaults = {
    mcpServers = {},
    timeout = 20000,
  },
  parameters = {
    protocolVersion = 1,
    clientCapabilities = {
      fs = { readTextFile = true, writeTextFile = true },
    },
    clientInfo = {
      name = "CodeCompanion.nvim",
      version = "1.0.0",
    },
  },
  handlers = {
    setup = function(self)
      return true
    end,
    auth = function(self)
      return true
    end,
    acp_request = handle_acp_request,
    form_messages = function(self, messages, capabilities)
      return helpers.form_messages(self, messages, capabilities)
    end,
    on_exit = function(self, code) end,
  },
}
