local new_set = MiniTest.new_set
local h = require("tests.helpers")

local T = MiniTest.new_set()

local config

T["Prompt Library"] = new_set({
  hooks = {
    pre_case = function()
      require("codecompanion").setup(h.config)
    end,
    post_once = function()
      h.teardown_chat_buffer()
    end,
  },
})

T["Prompt Library"]["can add references"] = function()
  require("codecompanion").prompt("test_ref")

  local chat = require("codecompanion").buf_get_chat(0)
  h.eq(2, #chat.refs)
  h.eq("<file>lua/codecompanion/health.lua</file>", chat.refs[1].id)
  h.eq("<file>lua/codecompanion/http.lua</file>", chat.refs[2].id)
end

return T
