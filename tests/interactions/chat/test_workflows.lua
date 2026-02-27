local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()

T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        config = require("tests.config")
      ]])
    end,
    post_case = function()
      child.lua([[
        _G.chat = nil
      ]])
    end,
    post_once = child.stop,
  },
})

T["Workflows"] = new_set()

T["Workflows"]["prompts are sequentially added to the chat buffer"] = function()
  child.lua([[
    local strat = require("codecompanion.interactions")
    local adapters = require("codecompanion.adapters")

    _G.chat = strat
      .new({
        buffer_context = { bufnr = 0, filetype = "lua" },
        selected = {
          adapter = adapters.extend({
            name = "TestAdapter",
            formatted_name = "Test Adapter",
            url = "https://api.openai.com/v1/chat/completions",
            roles = { llm = "assistant", user = "user" },
            headers = { content_type = "application/json" },
            parameters = { stream = true },
            handlers = {
              form_parameters = function() return {} end,
              form_messages = function() return {} end,
              is_complete = function() return false end,
            },
            schema = { model = { default = "gpt-3.5-turbo" } },
          }),
          description = "Test Workflow",
          name = "Code workflow",
          strategy = "workflow",
          opts = { index = 4 },
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
                condition = function(chat)
                  return chat.tools.tool and chat.tools.tool.name == "run_command"
                end,
                repeat_until = function(chat)
                  return chat.tool_registry.flags.testing == true
                end,
                content = "The tests have failed",
              },
            },
            {
              {
                name = "Success",
                role = "user",
                opts = { auto_submit = false },
                condition = function(chat)
                  return not chat.tools.tool
                end,
                content = "Tests passed!",
              },
            },
          },
        },
      })
      :start("workflow")
  ]])

  -- Initial prompt is shown
  local last_line = child.lua([[
    local lines = h.get_buf_lines(_G.chat.bufnr)
    return lines[#lines]
  ]])
  h.eq("First prompt", last_line)

  -- Mock failing tool, twice
  child.lua([[_G.chat.tools.tool = { name = "run_command" }]])
  child.lua([[h.send_to_llm(_G.chat, "Calling a tool...")]])
  last_line = child.lua([[
    local lines = h.get_buf_lines(_G.chat.bufnr)
    return lines[#lines]
  ]])
  h.eq("The tests have failed", last_line)

  child.lua([[_G.chat.tools.tool = { name = "run_command" }]])
  child.lua([[h.send_to_llm(_G.chat, "Calling a tool...")]])
  last_line = child.lua([[
    local lines = h.get_buf_lines(_G.chat.bufnr)
    return lines[#lines]
  ]])
  h.eq("The tests have failed", last_line)

  -- Now pass tests; unset tool after this turn
  child.lua([[
    _G.chat.tool_registry.flags.testing = true
    h.send_to_llm(_G.chat, "Calling a tool...", function() _G.chat.tools.tool = nil end)
  ]])
  last_line = child.lua([[
    local lines = h.get_buf_lines(_G.chat.bufnr)
    return lines[#lines]
  ]])
  h.eq("Tests passed!", last_line)

  -- Ensure there are no actionable subscribers left (conditions/order prevent further actions)
  local actionable = child.lua([[
    local count = 0
    for _, s in ipairs(_G.chat.subscribers.queue) do
      local ok = true
      if s.order and s.order >= _G.chat.cycle then
        ok = false
      end
      if ok and type(s.data.condition) == "function" then
        if not s.data.condition(_G.chat) then ok = false end
      end
      if ok then count = count + 1 end
    end
    return count
  ]])
  h.eq(0, actionable)

  -- Chat should be back to normal: next turn shows blank user prompt line after sending
  child.lua([[h.send_to_llm(_G.chat, "What should we do now?")]])
  last_line = child.lua([[
    local lines = h.get_buf_lines(_G.chat.bufnr)
    return lines[#lines]
  ]])

  h.eq("", last_line)
end

return T
