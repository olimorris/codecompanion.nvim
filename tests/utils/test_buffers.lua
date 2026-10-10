local h = require("tests.helpers")

local test_text = {
  "function hello()",
  "  print('Hello, World!')",
  "  return true",
  "end",
}

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)

      child.lua(string.format(
        [[
        _G.buf_utils = require("codecompanion.utils.buffers")
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
    post_case = function()
      child.lua([[
        if _G.test_buffer and vim.api.nvim_buf_is_valid(_G.test_buffer) then
          vim.api.nvim_buf_delete(_G.test_buffer, { force = true })
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["Utils->Buffers"] = new_set()

T["Utils->Buffers"]["add_line_numbers works"] = function()
  local result = child.lua([[
    local content = "hello\nworld\ntest"
    return _G.buf_utils.add_line_numbers(content)
  ]])

  h.expect_match(result, "1 |hello")
  h.expect_match(result, "2 |world")
  h.expect_match(result, "3 |test")
end

T["Utils->Buffers"]["get_bufnr_from_path finds a buffer opened through a symlink"] = function()
  local result = child.lua([[
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. "/real", "p")
    vim.uv.fs_symlink(dir .. "/real", dir .. "/link")
    vim.fn.writefile({ "local x = 1" }, dir .. "/real/file.lua")

    vim.cmd("edit " .. dir .. "/real/file.lua")
    return { expected = vim.api.nvim_get_current_buf(), found = _G.buf_utils.get_bufnr_from_path(dir .. "/link/file.lua") }
  ]])
  h.eq(result.expected, result.found)
end

return T
