local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[ h = require('tests.helpers') ]])
    end,
    post_once = child.stop,
  },
})

T["Connection forwards permission requests to active prompt"] = function()
  local result = child.lua([[
    local Connection = require("codecompanion.acp")

    local adapter = {
      handlers = { form_messages = function(_, msgs) return msgs end },
      defaults = {},
      commands = { default = "noop" },
    }

    local conn = Connection.new({ adapter = adapter })

    local forwarded = {}
    conn._active_prompt = {
      _handle_permission_request = function(_, id, params)
        forwarded.id = id
        forwarded.params = params
      end
    }

    local notif = {
      jsonrpc = "2.0",
      id = 42,
      method = "session/request_permission",
      params = {
        sessionId = "sess-1",
        options = {
          { optionId = "opt-1", name = "Allow once", kind = "allow_once" },
        },
        toolCall = {
          toolCallId = "tc-1",
          status = "pending",
          title = "Run something",
          content = {},
          kind = "execute",
        },
      },
    }

    conn:_process_notification(notif)

    return {
      id = forwarded.id,
      sessionId = forwarded.params and forwarded.params.sessionId or nil,
      toolCallId = forwarded.params and forwarded.params.toolCall and forwarded.params.toolCall.toolCallId or nil,
    }
  ]])

  h.eq(42, result.id)
  h.eq("sess-1", result.sessionId)
  h.eq("tc-1", result.toolCallId)
end

T["PromptBuilder sends selected outcome response"] = function()
  local result = child.lua([[
    local Connection = require("codecompanion.acp")

    local adapter = {
      handlers = { form_messages = function(_, msgs) return msgs end },
      defaults = {},
      commands = { default = "noop" },
    }

    local conn = Connection.new({ adapter = adapter })
    conn.session_id = "test-session-2"

    _G.captured = nil
    conn._write_to_process = function(self, data)
      _G.captured = data
      return true
    end

    local pb = conn:prompt({ { type = "text", text = "hi" } })

    pb:on_permission_request(function(req)
      req.respond("opt-2", false)
    end)

    local params = {
      sessionId = "sess-2",
      options = {
        { optionId = "opt-1", name = "Always allow", kind = "allow_always" },
        { optionId = "opt-2", name = "Allow once",   kind = "allow_once"   },
      },
      toolCall = {
        toolCallId = "tc-2",
        status = "pending",
        title = "Execute",
        content = {},
        kind = "execute",
      },
    }

    pb:_handle_permission_request(7, params)

    local sent = vim.json.decode(_G.captured or "{}")
    return {
      id = sent.id,
      outcome = sent.result and sent.result.outcome and sent.result.outcome.outcome or nil,
      optionId = sent.result and sent.result.outcome and sent.result.outcome.optionId or nil,
    }
  ]])

  h.eq(7, result.id)
  h.eq("selected", result.outcome)
  h.eq("opt-2", result.optionId)
end

T["PromptBuilder auto-cancels when no handler is registered"] = function()
  local result = child.lua([[
    local Connection = require("codecompanion.acp")

    local adapter = {
      handlers = { form_messages = function(_, msgs) return msgs end },
      defaults = {},
      commands = { default = "noop" },
    }

    local conn = Connection.new({ adapter = adapter })
    conn.session_id = "test-session-3"

    _G.captured = nil
    conn._write_to_process = function(self, data)
      _G.captured = data
      return true
    end

    local pb = conn:prompt({ { type = "text", text = "hello" } })

    local params = {
      sessionId = "sess-3",
      options = {
        { optionId = "opt-1", name = "Allow", kind = "allow_once" },
      },
      toolCall = {
        toolCallId = "tc-3",
        status = "pending",
        title = "Edit file",
        content = {},
        kind = "edit",
      },
    }

    pb:_handle_permission_request(13, params)

    local sent = vim.json.decode(_G.captured or "{}")
    return {
      id = sent.id,
      outcome = sent.result and sent.result.outcome and sent.result.outcome.outcome or nil,
      has_optionId = sent.result and sent.result.outcome and sent.result.outcome.optionId ~= nil,
    }
  ]])

  h.eq(13, result.id)
  h.eq("canceled", result.outcome)
  h.eq(false, result.has_optionId)
end

return T
