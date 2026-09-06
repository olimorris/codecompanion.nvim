local h = require("tests.helpers")
local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local RESPONSE_WITH_UNCLOSED_FENCE = "Here you go:\n\n````lua\nlocal x = 1\n"
local RESPONSE_WITH_CLOSED_FENCE = "Here you go:\n\n````lua\nlocal x = 1\n````\n"

---@param response string
---@param lines string[]
local function add_response(response, lines)
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

---What `Chat:submit()` would extract as the user's message
---@return { content?: string }
local function get_extracted_message()
  return child.lua_get([[(function()
    local parser = require('codecompanion.interactions.chat.parser')
    local message = parser.messages(_G.chat, _G.chat.header_line)
    return { content = message and message.content }
  end)()]])
end

---The header row the parser reports, against the last one actually in the buffer
---@return { reported?: number, actual?: number }
local function get_header_rows()
  return child.lua_get([[(function()
    local parser = require('codecompanion.interactions.chat.parser')
    local actual
    for i, line in ipairs(vim.api.nvim_buf_get_lines(_G.chat.bufnr, 0, -1, false)) do
      if line:match('^## ') then
        actual = i - 1
      end
    end
    return { reported = parser.headers(_G.chat), actual = actual }
  end)()]])
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

T["Parser"] = new_set()

T["Parser"]["Can extract a prompt after a closed code fence"] = function()
  add_response(RESPONSE_WITH_CLOSED_FENCE, { "please fix the bug" })
  h.eq("please fix the bug", get_extracted_message().content)
end

T["Parser"]["Can extract a prompt after an unclosed code fence"] = function()
  add_response(RESPONSE_WITH_UNCLOSED_FENCE, { "please fix the bug" })
  h.eq("please fix the bug", get_extracted_message().content)
end

T["Parser"]["Finds the last user header behind an unclosed code fence"] = function()
  add_response(RESPONSE_WITH_UNCLOSED_FENCE, { "please fix the bug" })
  local rows = get_header_rows()
  h.eq(rows.actual, rows.reported)
end

T["Parser"]["Strips context from a recovered prompt"] = function()
  add_response(RESPONSE_WITH_UNCLOSED_FENCE, { "> Context:", "> - <file>foo.lua</file>", "", "please fix the bug" })
  h.eq("please fix the bug", get_extracted_message().content)
end

T["Parser"]["Recovers a multi-line prompt in full"] = function()
  add_response(RESPONSE_WITH_UNCLOSED_FENCE, { "first line", "", "second line" })
  h.eq("first line\n\nsecond line", get_extracted_message().content)
end

T["Parser"]["Returns no message for an empty user section"] = function()
  add_response(RESPONSE_WITH_CLOSED_FENCE, {})
  h.eq(nil, get_extracted_message().content)
end

T["Parser"]["Returns no message for an empty user section under an unclosed fence"] = function()
  add_response(RESPONSE_WITH_UNCLOSED_FENCE, {})
  h.eq(nil, get_extracted_message().content)
end

return T
