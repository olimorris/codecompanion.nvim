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
        codecompanion = require("codecompanion")
        h = require('tests.helpers')
        _G.chat, _G.agent = h.setup_chat_buffer()
        ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["Chat"] = new_set()

T["Chat"]["system prompt is added first"] = function()
  local messages = child.lua_get([[_G.chat.messages]])
  h.eq("system", messages[1].role)
  h.eq("default system prompt", messages[1].content)
end

T["Chat"]["buffer variables are handled"] = function()
  -- Execute all the complex operations in the child process
  child.lua([[
    -- Get the existing chat object
    local chat = _G.chat

    -- Add a new message with a variable reference
    table.insert(chat.messages, { role = "user", content = "#{foo} what does this file do?" })

    -- Get the message we just added
    local message = chat.messages[#chat.messages]

    -- Parse and replace variables in the message
    if chat.variables:parse(chat, message) then
      message.content = chat.variables:replace(message.content, chat.context.bufnr)
    end

    -- Extract the properties we need to test into simple data types
    _G.last_message_content = chat.messages[#chat.messages].content
    _G.last_message_visible = chat.messages[#chat.messages].opts.visible
    _G.last_message_tag = chat.messages[#chat.messages].opts.tag
  ]])

  -- Retrieve the simple values from the child process
  local last_message_content = child.lua_get([[_G.last_message_content]])
  local last_message_visible = child.lua_get([[_G.last_message_visible]])
  local last_message_tag = child.lua_get([[_G.last_message_tag]])

  -- Make assertions on the retrieved values
  h.eq("foo", last_message_content)
  h.eq(false, last_message_visible)
  h.eq("variable", last_message_tag)
end

T["Chat"]["system prompt can be ignored"] = function()
  child.lua([[_G.new_chat = require("codecompanion.strategies.chat").new({
    ignore_system_prompt = true,
  })]])

  local new_chat = child.lua_get([[_G.new_chat.messages]])

  h.eq(nil, new_chat[1])
end

T["Chat"]["chat buffer is initialized"] = function()
  child.lua([[require("codecompanion").chat()]])
  expect.reference_screenshot(child.get_screenshot())
end

T["Chat"]["loading from the prompt library sets the correct header_line"] = function()
  local output = child.lua([[
    --require("tests.log")
    -- Load the demo prompt from the prompt library
    codecompanion.prompt("demo")
    -- Get the chat object
    local bufnr = vim.api.nvim_get_current_buf()
    local chat = codecompanion.buf_get_chat(bufnr)
    return chat.header_line
  ]])

  expect.reference_screenshot(child.get_screenshot())
  h.eq(9, output)
end

T["Chat"]["prompt decorator is applied prior to sending to the LLM"] = function()
  local prompt = "Testing out the prompt decorator"
  local output = child.lua(string.format(
    [[
      local config = require("codecompanion.config")
      config.strategies.chat.opts.prompt_decorator = function(message)
        return "<prompt>" .. message .. "</prompt>"
      end
      _G.chat:add_buf_message({
        role = "user",
        content = "%s",
      })
      _G.chat:submit()
      return _G.chat.messages[#_G.chat.messages].content
  ]],
    prompt
  ))

  h.eq("<prompt>" .. prompt .. "</prompt>", output)
end

T["Chat"]["images are replaced in text and base64 encoded"] = function()
  local prompt = string.format("What does this [Image](%s) do?", vim.fn.getcwd() .. "/tests/stubs/logo.png")
  local message = child.lua(string.format(
    [[
      _G.chat:add_buf_message({
        role = "user",
        content = "%s",
      })
      _G.chat:submit()
      local messages = _G.chat.messages
      return messages[#messages - 1].content
  ]],
    prompt
  ))

  h.eq("What does this image do?", message)

  if vim.fn.executable("base64") == 0 then
    MiniTest.skip("base64 is not installed, skipping test")
  end

  message = child.lua([[
    local messages = _G.chat.messages
    return messages[#messages]
  ]])

  h.eq({
    mimetype = "image/png",
    reference = string.format("<image>%s/tests/stubs/logo.png</image>", vim.fn.getcwd()),
    tag = "image",
    visible = false,
  }, message.opts)

  h.expect_starts_with("iVBORw0KGgoAAAANSUhEU", message.content)
end

local get_lines = function()
  return child.api.nvim_buf_get_lines(0, 0, -1, true)
end

T["Chat"]["can bring up keymap options in the chat buffer"] = function()
  child.lua([[
    -- Open the chat buffer
    require("codecompanion").chat()

    -- Ensure we're in normal mode
    vim.cmd("stopinsert")
  ]])

  child.type_keys("?")
  vim.loop.sleep(200)

  h.eq(get_lines()[1], "### Keymaps")
end

T["Chat"]["can load default tools"] = function()
  local refs = child.lua([[
    codecompanion = require("codecompanion")
    h = require('tests.helpers')
    _G.chat, _G.agent = h.setup_chat_buffer({
      strategies = {
        chat = {
          tools = {
            opts = {
              default_tools = { "weather", "tool_group" }
            }
          }
        }
      }
    })

    return _G.chat.refs
  ]])
  h.eq(
    { "<tool>weather</tool>", "<group>tool_group</group>", "<tool>func</tool>", "<tool>cmd</tool>" },
    vim
      .iter(refs)
      :map(function(item)
        return item.id
      end)
      :totable()
  )
end

return T
