local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local test_text = {
  "function hello()",
  "  print('Hello, World!')",
  "  return true",
  "end",
}

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)

      child.lua(string.format(
        [[
        _G.helpers = require("codecompanion.interactions.chat.helpers")
        _G.test_text = %s
        _G.test_buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(_G.test_buffer, 0, -1, false, _G.test_text)
        vim.api.nvim_buf_set_option(_G.test_buffer, "filetype", "lua")
        vim.api.nvim_set_current_buf(_G.test_buffer)
        vim.opt.showmode = false
      ]],
        vim.inspect(test_text)
      ))
    end,
    post_once = child.stop,
  },
})

T["format_buffer_for_llm works"] = function()
  local result = child.lua([[
    local content, id, filename = _G.helpers.format_buffer_for_llm(_G.test_buffer, "test_file.lua", { message = "Test message" })
    return { content = content, id = id, filename = filename }
  ]])

  -- Just check the basic structure is there
  h.expect_match(result.content, "<attachment")
  h.expect_match(result.content, "Test message:")
  h.expect_match(result.content, "```lua")
  h.expect_match(result.content, "function hello")
  h.expect_match(result.content, "</attachment>")

  h.eq(result.filename, "test_file.lua")
end

T["format_viewport_for_llm works"] = function()
  local result = child.lua([[
    -- Mock visible lines data structure
    local buf_lines = {
      [_G.test_buffer] = {{1, 2}} -- Lines 1-2 visible
    }
    return _G.helpers.format_viewport_for_llm(buf_lines)
  ]])

  h.expect_match(result, "<attachment")
  h.expect_match(result, "Excerpt from")
  h.expect_match(result, "lines 1 to 2")
end

T["create_acp_connection_async"] = new_set()

T["create_acp_connection_async"]["calls callback with false on connection failure"] = function()
  local result = child.lua([[
    local callback_called = false
    local callback_success = nil

    -- Mock the acp module
    package.loaded["codecompanion.acp"] = {
      new = function(opts)
        return {
          connect_and_initialize_async = function(self, cb)
            cb(nil, "connection failed")
          end,
        }
      end,
    }

    -- Mock chat object
    local mock_chat = {
      adapter = {},
      bufnr = 1,
      acp_connection = nil,
      update_metadata = function() end,
    }

    _G.helpers.create_acp_connection_async(mock_chat, function(success)
      callback_called = true
      callback_success = success
    end)

    return { callback_called = callback_called, callback_success = callback_success, acp_connection = mock_chat.acp_connection }
  ]])

  h.eq(result.callback_called, true)
  h.eq(result.callback_success, false)
  h.eq(result.acp_connection, nil)
end

T["create_acp_connection_async"]["calls callback with true on successful connection"] = function()
  local result = child.lua([[
    local callback_called = false
    local callback_success = nil
    local metadata_updated = false
    local buffer_linked = false

    -- Mock the acp_commands module
    package.loaded["codecompanion.interactions.chat.acp.commands"] = {
      link_buffer_to_session = function(bufnr, session_id)
        buffer_linked = true
      end,
    }

    -- Mock the acp module
    package.loaded["codecompanion.acp"] = {
      new = function(opts)
        return {
          session_id = "test-session-123",
          connect_and_initialize_async = function(self, cb)
            cb(self, nil)
          end,
        }
      end,
    }

    -- Mock chat object
    local mock_chat = {
      adapter = {},
      bufnr = 1,
      acp_connection = nil,
      update_metadata = function()
        metadata_updated = true
      end,
    }

    _G.helpers.create_acp_connection_async(mock_chat, function(success)
      callback_called = true
      callback_success = success
    end)

    return {
      callback_called = callback_called,
      callback_success = callback_success,
      has_connection = mock_chat.acp_connection ~= nil,
      metadata_updated = metadata_updated,
      buffer_linked = buffer_linked,
    }
  ]])

  h.eq(result.callback_called, true)
  h.eq(result.callback_success, true)
  h.eq(result.has_connection, true)
  h.eq(result.metadata_updated, true)
  h.eq(result.buffer_linked, true)
end

T["create_acp_connection_async"]["works without callback"] = function()
  local result = child.lua([[
    -- Mock the acp module
    package.loaded["codecompanion.acp"] = {
      new = function(opts)
        return {
          connect_and_initialize_async = function(self, cb)
            cb(nil, "connection failed")
          end,
        }
      end,
    }

    -- Mock chat object
    local mock_chat = {
      adapter = {},
      bufnr = 1,
      acp_connection = nil,
      update_metadata = function() end,
    }

    -- Should not error when called without callback
    local ok, err = pcall(function()
      _G.helpers.create_acp_connection_async(mock_chat)
    end)

    return { ok = ok, err = err }
  ]])

  h.eq(result.ok, true)
end

return T
