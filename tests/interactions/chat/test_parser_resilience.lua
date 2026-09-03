-- An unterminated fence hides the last `## <user>` header from queries/markdown/chat.scm,
-- so the typed prompt is dropped on submit. These cases pin the recovery.
local h = require("tests.helpers")
local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local UNTERMINATED = "Here you go:\n\n````lua\nlocal x = 1\n"
local BALANCED = "Here you go:\n\n````lua\nlocal x = 1\n````\n"

---Add `response` as the LLM's answer, then type `lines` under a fresh user header
---@param response string
---@param lines string[]
local function chat_with(response, lines)
  child.lua(
    [[
    local response, typed = ...
    _G.chat:add_buf_message({ role = 'llm', content = response })
    _G.chat:add_buf_message({ role = 'user', content = '' })
    -- Mirrors Chat:ready_for_input()
    _G.chat.header_line = (_G.chat.builder.state.current_header_line or 0) + 1
    if #typed > 0 then
      vim.api.nvim_buf_set_lines(_G.chat.bufnr, -1, -1, false, typed)
    end
  ]],
    { response, lines }
  )
end

---What `Chat:submit()` would extract, plus the reported and actual header rows
---@return { content?: string, header?: number, expected_header?: number }
local function extracted()
  return child.lua_get([[(function()
    local parser = require('codecompanion.interactions.chat.parser')
    local message = parser.messages(_G.chat, _G.chat.header_line)
    local lines = vim.api.nvim_buf_get_lines(_G.chat.bufnr, 0, -1, false)
    local last_header
    for i, line in ipairs(lines) do
      if line:match('^## ') then
        last_header = i - 1
      end
    end
    return {
      content = message and message.content,
      header = parser.headers(_G.chat),
      expected_header = last_header,
    }
  end)()]])
end

---Record what the parser reports through `log:warn`
---
---That handler is registered at `vim.log.levels.WARN`, so a warning also reaches
---`vim.notify`. The offending fence is never rewritten and so stays broken for the
---rest of the conversation, which is why a given buffer must be reported once
---rather than on every submit.
---@return nil
local function spy_on_warnings()
  child.lua([[
    _G.warnings = {}
    local log = require('codecompanion.utils.log')
    log.warn = function(_, msg)
      table.insert(_G.warnings, msg)
    end
  ]])
end

local function warning_count()
  return child.lua_get("#_G.warnings")
end

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        _G.chat = h.setup_chat_buffer()
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["Parser resilience"] = new_set()

T["Parser resilience"]["a balanced response leaves the prompt extractable"] = function()
  chat_with(BALANCED, { "please fix the bug" })
  h.eq("please fix the bug", extracted().content)
end

T["Parser resilience"]["an unterminated fence does not eat the next prompt"] = function()
  chat_with(UNTERMINATED, { "please fix the bug" })
  h.eq("please fix the bug", extracted().content)
end

T["Parser resilience"]["an unterminated fence does not hide the last user header"] = function()
  chat_with(UNTERMINATED, { "please fix the bug" })
  local result = extracted()
  h.eq(result.expected_header, result.header)
end

T["Parser resilience"]["context lines are stripped from the recovered prompt"] = function()
  chat_with(UNTERMINATED, { "> Context:", "> - <file>foo.lua</file>", "", "please fix the bug" })
  h.eq("please fix the bug", extracted().content)
end

T["Parser resilience"]["a multi-line prompt is recovered whole"] = function()
  chat_with(UNTERMINATED, { "first line", "", "second line" })
  h.eq("first line\n\nsecond line", extracted().content)
end

T["Parser resilience"]["an empty user section still yields no message"] = function()
  -- Tool auto-submits rely on this: recovery must not fabricate a prompt.
  chat_with(BALANCED, {})
  h.eq(nil, extracted().content)
end

T["Parser resilience"]["an empty user section under a broken fence yields no message"] = function()
  chat_with(UNTERMINATED, {})
  h.eq(nil, extracted().content)
end

T["Parser resilience"]["recovery is reported once, not on every parse"] = function()
  chat_with(UNTERMINATED, { "please fix the bug" })
  spy_on_warnings()

  h.eq("please fix the bug", extracted().content)
  h.eq("please fix the bug", extracted().content)

  h.eq(1, warning_count())
  h.expect_contains("unterminated code fence", child.lua_get("_G.warnings[1]"))
end

T["Parser resilience"]["a healthy buffer is parsed without warning"] = function()
  chat_with(BALANCED, { "please fix the bug" })
  spy_on_warnings()

  h.eq("please fix the bug", extracted().content)
  h.eq(0, warning_count())
end

return T
