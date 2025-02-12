local codecompanion = require("codecompanion")
local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = MiniTest.new_set()

T["Inline"] = new_set({
  hooks = {
    pre_case = function() end,
    post_case = function() end,
  },
})

T["Inline"]["can be prompted from the cmdline"] = function()
  -- 1. Set up test environment
  local child = h.new_child_neovim()
  child.setup()

  -- 2. Mock necessary components/functions
  -- Since inline prompt uses vim.ui.input, we should mock it
  child.lua([[
    _G.input_args = nil
    vim.ui.input = function(opts, cb)
      _G.input_args = opts
      -- Simulate user entering "write a hello world function"
      cb("write a hello world function")
    end
  ]])

  -- 3. Create test command arguments
  local prompt = {
    args = "write a hello world function",
    bang = false,
    count = -1,
    fargs = { "write", "a", "hello", "world", "function" },
    line1 = 1,
    line2 = 1,
  }

  -- 4. Execute the inline command
  child.lua(
    [[
    local codecompanion = require('codecompanion')
    local output = codecompanion.inline(...)
  ]],
    { prompt }
  )

  -- 5. Verify the input prompt was shown correctly
  local input_args = child.lua_get("_G.input_args")
  -- h.eq(input_args.prompt, "Lua Action") -- Assuming filetype is Lua

  -- 6. Wait for and verify the output in the buffer
  vim.wait(1000, function()
    local lines = child.api.nvim_buf_get_lines(0, 0, -1, true)
    return #lines > 0 and lines[1]:match("function") ~= nil
  end)

  local final_lines = child.api.nvim_buf_get_lines(0, 0, -1, true)
  h.expect_match(table.concat(final_lines, "\n"), "function")
  print(vim.inspect(final_lines))

  -- 7. Clean up
  child.stop()
end
T["Inline"]["can prompt for placement"] = function() end
T["Inline"]["can ignore placement"] = function() end
T["Inline"]["can include buffer contents"] = function() end

return T
