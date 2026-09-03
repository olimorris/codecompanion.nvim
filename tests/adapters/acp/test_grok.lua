local h = require("tests.helpers")

local new_set = MiniTest.new_set
local question_prompt = require("codecompanion.interactions.chat.helpers.question_prompt")
local original_ask = question_prompt.ask
local original_input = vim.ui.input

local T = new_set({
  hooks = {
    post_case = function()
      question_prompt.ask = original_ask
      vim.ui.input = original_input
    end,
  },
})

local function request(params, method)
  local captured = {}
  return {
    chat = {
      MESSAGE_TYPES = { LLM_MESSAGE = 1 },
      add_buf_message = function(_, message)
        captured.message = message.content
      end,
    },
    method = method or "_x.ai/ask_user_question",
    params = params,
    on_cancel = function(callback)
      captured.cancel = callback
    end,
    reject = function(message, code)
      captured.error = { message = message, code = code }
    end,
    respond = function(response)
      captured.response = response
    end,
  },
    captured
end

T["Grok adapter"] = new_set()

T["Grok adapter"]["uses the official ACP command"] = function()
  local adapter = require("codecompanion.adapters.acp.grok")
  h.eq({ "grok", "agent", "stdio" }, adapter.commands.default)
  h.eq("Grok Build", adapter.formatted_name)
end

T["Grok adapter"]["answers Grok's wrapped question request"] = function()
  question_prompt.ask = function(_, opts)
    opts.callback("Python")
    return function() end
  end

  local adapter = require("codecompanion.adapters.acp.grok")
  local req, captured = request({
    method = "x.ai/ask_user_question",
    params = {
      sessionId = "session-1",
      questions = {
        {
          question = "Which language?",
          options = {
            { label = "Python" },
            { label = "Rust" },
          },
        },
      },
    },
  })

  h.is_true(adapter.handlers.acp_request(adapter, req))
  h.eq("accepted", captured.response.outcome)
  h.eq({ "Python" }, captured.response.answers["Which language?"])
end

T["Grok adapter"]["preserves custom answers as annotations"] = function()
  question_prompt.ask = function(_, opts)
    opts.callback("Use Zig")
    return function() end
  end

  local adapter = require("codecompanion.adapters.acp.grok")
  local req, captured = request({
    sessionId = "session-1",
    questions = {
      {
        question = "Which language?",
        options = { { label = "Python" }, { label = "Rust" } },
      },
    },
  })

  adapter.handlers.acp_request(adapter, req)
  h.eq({ "Other" }, captured.response.answers["Which language?"])
  h.eq("Use Zig", captured.response.annotations["Which language?"].notes)
end

T["Grok adapter"]["omits skipped questions from an accepted response"] = function()
  question_prompt.ask = function(_, opts)
    opts.callback(nil)
    return function() end
  end

  local adapter = require("codecompanion.adapters.acp.grok")
  local req, captured = request({
    sessionId = "session-1",
    questions = {
      {
        question = "Which language?",
        options = { { label = "Python" }, { label = "Rust" } },
      },
    },
  })

  adapter.handlers.acp_request(adapter, req)
  h.eq("accepted", captured.response.outcome)
  h.eq("{}", vim.json.encode(captured.response.answers))
end

T["Grok adapter"]["returns the user's plan decision"] = function()
  question_prompt.ask = function(_, opts)
    opts.callback("Approve")
    return function() end
  end

  local adapter = require("codecompanion.adapters.acp.grok")
  local req, captured = request({
    sessionId = "session-1",
    planContent = "1. Inspect the project\n2. Make the change",
  }, "_x.ai/exit_plan_mode")

  adapter.handlers.acp_request(adapter, req)
  h.eq("approved", captured.response.outcome)
  h.expect_contains("Inspect the project", captured.message)
end

T["Grok adapter"]["returns plan feedback using Grok's cancelled outcome"] = function()
  question_prompt.ask = function(_, opts)
    opts.callback("Request changes")
    return function() end
  end
  vim.ui.input = function(_, callback)
    callback("Use async I/O")
  end

  local adapter = require("codecompanion.adapters.acp.grok")
  local req, captured = request({
    sessionId = "session-1",
    planContent = "1. Make the change",
  }, "_x.ai/exit_plan_mode")

  adapter.handlers.acp_request(adapter, req)
  h.eq("cancelled", captured.response.outcome)
  h.eq("Use async I/O", captured.response.feedback)
end

return T
