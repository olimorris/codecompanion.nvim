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

return T
