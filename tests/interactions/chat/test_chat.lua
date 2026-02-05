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
        _G.chat, _G.tools = h.setup_chat_buffer()
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

    -- Add a new message with a variable context
    table.insert(chat.messages, { role = "user", content = "#{foo} what does this file do?" })

    -- Get the message we just added
    local message = chat.messages[#chat.messages]

    -- Parse and replace variables in the message
    if chat.variables:parse(chat, message) then
      message.content = chat.variables:replace(message.content, chat.buffer_context.bufnr)
    end

    -- Extract the properties we need to test into simple data types
    _G.last_message_content = chat.messages[#chat.messages].content
    _G.last_message_visible = chat.messages[#chat.messages].opts.visible
    _G.last_message_tag = chat.messages[#chat.messages]._meta.tag
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
  child.lua([[_G.new_chat = require("codecompanion.interactions.chat").new({
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
      config.interactions.chat.opts.prompt_decorator = function(message)
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
  local prompt =
    string.format("What does this [Image](%s) do?", vim.fs.normalize(vim.fn.getcwd()) .. "/tests/stubs/logo.png")
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

  message = child.lua([[
    local messages = _G.chat.messages
    return messages[#messages]
  ]])

  h.eq({
    visible = false,
  }, message.opts)

  h.eq({
    cycle = 1,
    index = message._meta.index,
    id = message._meta.id,
    tag = "image",
  }, message._meta)

  h.eq({
    id = string.format("<image>%s/tests/stubs/logo.png</image>", vim.fs.normalize(vim.fn.getcwd())),
    mimetype = "image/png",
    path = string.format("%s/tests/stubs/logo.png", vim.fs.normalize(vim.fn.getcwd())),
  }, message.context)

  h.expect_starts_with("iVBORw0KGgoAAAANSUhEU", message.content)
end

local get_lines = function()
  return child.api.nvim_buf_get_lines(0, 0, -1, true)
end

T["Chat"]["can bring up keymap options in the chat buffer"] = function()
  child.lua([[
    require("codecompanion").chat()
    vim.cmd("stopinsert") -- Ensure we're in normal mode
  ]])

  child.type_keys("?")
  vim.loop.sleep(200)

  h.eq(get_lines()[1], "### Keymaps")
end

T["Chat"]["can load default tools"] = function()
  local ctx = child.lua([[
    codecompanion = require("codecompanion")
    h = require('tests.helpers')

    _G.chat, _G.tools = h.setup_chat_buffer({
      interactions = {
        chat = {
          tools = {
            opts = {
              default_tools = { "weather", "tool_group" }
            }
          }
        }
      }
    })

    return _G.chat.context_items
  ]])
  h.eq(
    { "<tool>weather</tool>", "<group>tool_group</group>", "<tool>func</tool>", "<tool>cmd</tool>" },
    vim
      .iter(ctx)
      :map(function(item)
        return item.id
      end)
      :totable()
  )
end

T["Chat"]["ftplugin window options override plugin defaults"] = function()
  -- This test verifies that user's after/ftplugin/codecompanion.lua can override
  -- the plugin's default window options. This ensures setting filetype
  -- after window options is working correctly.
  local child_test = MiniTest.new_child_neovim()
  h.child_start(child_test)

  child_test.lua([[
    -- Create a temporary directory for our test ftplugin
    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir .. "/after/ftplugin", "p")

    -- Write a test ftplugin that sets custom window options
    -- These intentionally differ from plugin defaults to verify override behavior
    local ftplugin_lines = {
      "vim.wo.wrap = false",
      "vim.wo.number = true",
      "vim.wo.relativenumber = true",
    }
    local ftplugin_path = temp_dir .. "/after/ftplugin/codecompanion.lua"
    vim.fn.writefile(ftplugin_lines, ftplugin_path)

    -- Store paths for cleanup
    _G.test_temp_dir = temp_dir
    _G.test_ftplugin_path = ftplugin_path

    h = require('tests.helpers')

    -- Setup codecompanion
    local codecompanion = h.setup_plugin()
    codecompanion.setup()
    codecompanion.chat()

    -- Manually source the ftplugin file to simulate user's after/ftplugin
    -- This is needed because Neovim won't automatically re-source ftplugin
    -- files for filetypes that have already been seen in the test environment
    vim.cmd("source " .. vim.fn.fnameescape(ftplugin_path))

    -- Get the current window options
    local winnr = vim.api.nvim_get_current_win()
    local bufnr = vim.api.nvim_win_get_buf(winnr)
    _G.test_wrap = vim.wo[winnr].wrap
    _G.test_number = vim.wo[winnr].number
    _G.test_relativenumber = vim.wo[winnr].relativenumber
    _G.test_filetype = vim.bo[bufnr].filetype
  ]])

  -- Retrieve the window option values
  local wrap = child_test.lua_get([[_G.test_wrap]])
  local number = child_test.lua_get([[_G.test_number]])
  local relativenumber = child_test.lua_get([[_G.test_relativenumber]])
  local filetype = child_test.lua_get([[_G.test_filetype]])

  -- Verify filetype is set correctly
  h.eq("codecompanion", filetype)

  -- Assert that ftplugin settings override plugin defaults
  -- Plugin defaults: wrap=true, number=not set, relativenumber=not set
  -- User ftplugin sets: wrap=false, number=true, relativenumber=true
  h.eq(false, wrap)
  h.eq(true, number)
  h.eq(true, relativenumber)

  child_test.lua([[
    vim.fn.delete(_G.test_temp_dir, "rf")
  ]])

  child_test.stop()
end

T["Chat"]["can create hidden chat without opening window"] = function()
  local result = child.lua([[
    local hidden_chat = codecompanion.chat({
      hidden = true,
      messages = {
        { role = "user", content = "Test hidden chat" }
      }
    })

    local line_count = vim.api.nvim_buf_line_count(hidden_chat.bufnr)
    local cwd_ok, cwd_ctx = pcall(function() return hidden_chat:make_system_prompt_ctx() end)

    return {
      hidden = hidden_chat.hidden,
      bufnr_valid = vim.api.nvim_buf_is_valid(hidden_chat.bufnr),
      is_visible = hidden_chat.ui:is_visible(),
      line_count = line_count,
      buffer_has_content = line_count > 0,
      cwd_works = cwd_ok,
      cwd_value = cwd_ok and cwd_ctx.cwd or nil
    }
  ]])

  h.eq(true, result.hidden)
  h.eq(true, result.bufnr_valid)
  h.eq(false, result.is_visible == true)
  h.eq(true, result.line_count > 0)
  h.eq(true, result.cwd_works)
  h.eq(true, result.cwd_value ~= nil and result.cwd_value ~= "")
end

return T
