local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = MiniTest.new_set()

local chat

T["Workflows"] = new_set({
  hooks = {
    pre_case = function()
      -- h.setup_chat_buffer()
      chat = require("codecompanion.strategies")
        .new({
          context = { bufnr = 0, filetype = "lua" },
          selected = {
            adapter = require("codecompanion.adapters").extend({
              name = "TestAdapter",
              url = "https://api.openai.com/v1/chat/completions",
              roles = {
                llm = "assistant",
                user = "user",
              },
              headers = {
                content_type = "application/json",
              },
              parameters = {
                stream = true,
              },
              handlers = {
                form_parameters = function()
                  return {}
                end,
                form_messages = function()
                  return {}
                end,
                is_complete = function()
                  return false
                end,
              },
              schema = {
                model = {
                  default = "gpt-3.5-turbo",
                },
              },
            }),

            description = "Test Workflow",
            name = "Code workflow",
            strategy = "workflow",
            opts = {
              index = 4,
              is_default = true,
            },
            prompts = {
              {
                {
                  role = "user",
                  opts = { auto_submit = false },
                  content = "First prompt",
                },
              },
              {
                {
                  name = "Repeat On Failure",
                  role = "user",
                  opts = { auto_submit = false },
                  -- Scope this prompt to the cmd_runner tool
                  condition = function()
                    return _G.codecompanion_current_tool == "cmd_runner"
                  end,
                  -- Repeat until the tests pass, as indicated by the testing flag
                  -- which the cmd_runner tool sets on the chat buffer
                  repeat_until = function(chat)
                    return chat.tools.flags.testing == true
                  end,
                  content = "The tests have failed",
                },
              },
              {
                {
                  name = "Success",
                  role = "user",
                  opts = { auto_submit = false },
                  condition = function()
                    return not _G.codecompanion_current_tool
                  end,
                  content = "Tests passed!",
                },
              },
            },
          },
        })
        :start("workflow")
    end,
    post_case = function()
      h.teardown_chat_buffer()
    end,
  },
})

T["Workflows"]["prompts are sequentially added to the chat buffer"] = function()
  -- Initial prompt should be displayed in the chat buffer
  h.eq("First prompt", h.get_buf_lines(chat.bufnr)[#h.get_buf_lines(chat.bufnr)])

  -- Let's mock a failing tool test
  _G.codecompanion_current_tool = "cmd_runner"
  h.send_to_llm(chat, "Calling a tool...")
  h.eq("The tests have failed", h.get_buf_lines(chat.bufnr)[#h.get_buf_lines(chat.bufnr)])

  -- And again
  _G.codecompanion_current_tool = "cmd_runner"
  h.send_to_llm(chat, "Calling a tool...")
  h.eq("The tests have failed", h.get_buf_lines(chat.bufnr)[#h.get_buf_lines(chat.bufnr)])

  -- Now let's mock a passing test
  chat.tools.flags.testing = true
  h.send_to_llm(chat, "Calling a tool...", function()
    _G.codecompanion_current_tool = nil
  end)
  h.eq("Tests passed!", h.get_buf_lines(chat.bufnr)[#h.get_buf_lines(chat.bufnr)])

  -- There should be no subscribers
  h.eq(0, #chat.subscribers)

  -- Chat should be back to normal
  h.send_to_llm(chat, "What should we do now?")
  h.eq("", h.get_buf_lines(chat.bufnr)[#h.get_buf_lines(chat.bufnr)])
end

return T
