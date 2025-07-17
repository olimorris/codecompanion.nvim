local h = require("tests.helpers")

local expect = MiniTest.expect
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

T["Test tools in chat buffer"] = new_set({
  parametrize = {
    -- OpenAI type adapters first
    { "openai", "openai_tools" },
    { "copilot", "openai_tools" },
    { "gemini", "openai_tools" },
    -- Others
    { "anthropic", "anthropic_tools" },
    { "deepseek", "deepseek_tools" },
    { "ollama", "ollama_tools" },
  },
})

T["Test tools in chat buffer"]["with different adapters"] = function(adapter, file)
  local response = "tests/adapters/stubs/" .. file .. "_streaming.txt"
  local output = "tests/adapters/stubs/output/" .. file .. ".txt"

  -- Setup the chat with the specified adapter
  child.lua(string.format(
    [[
      -- Setup the chat buffer
      _G.chat = h.setup_chat_buffer(config, {
        name = "%s",
        config = require("codecompanion.adapters.%s")
      })

      -- Create a mocked submit method which we use to get the chat output and the tools
      _G.chat.mock_submit = function(self)
        local tools = {}
        local output = {}
        for _, line in ipairs(vim.fn.readfile("%s")) do
          -- This is a direct copy from chat/init.lua
          local result = self.adapter.handlers.chat_output(self.adapter, line, tools)
          if result and result.status then
            if result.output.role then
              result.output.role = config.constants.LLM_ROLE
            end
            table.insert(output, result.output.content)
            self:add_buf_message(result.output, { type = "llm_message" })
          end
        end
        return output, tools
      end

      -- We don't need to mock the done method but we do need to mock some of the methods it calls
      _G.chat.agents.execute = nil

      -- Force submit so that chat:done works
      _G.chat.status = "success"

      -- Just adding this to make the chat buffer look more real
      _G.chat:add_buf_message({
        role = "user",
        content = "What's the @{weather} like in London and Paris?"
      }, { type = "user_message" })
      _G.chat:add_message({
        role = "user",
        content = "What's the weather like in London and Paris?"
      })

      -- Submit the chat buffer!!
      _G.chat_output, _G.chat_tools = _G.chat:mock_submit()
      _G.chat:done(_G.chat_output, _, _G.chat_tools)
    ]],
    adapter,
    adapter,
    response
  ))

  local messages = child.lua([[
    -- Make sure we replace the roles with the adapter ones. This breaks up the Anthropic test otherwise
    local messages = _G.chat.adapter:map_roles(vim.deepcopy(_G.chat.messages))
    return _G.chat.adapter.handlers.form_messages(_G.chat.adapter, messages)
  ]])
  local reference = vim.json.decode(table.concat(vim.fn.readfile(output), "\n"))

  h.eq(messages, reference)

  expect.reference_screenshot(child.get_screenshot())
end

return T
