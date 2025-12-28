local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = MiniTest.new_set()

local child = MiniTest.new_child_neovim()

T["UI create_float Screenshots"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        _G.h = require('tests.helpers')
        h.setup_plugin()
      ]])
    end,
    post_case = function()
      child.lua([[
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_is_valid(win) then
            local config = vim.api.nvim_win_get_config(win)
            if config.relative ~= "" then
              pcall(vim.api.nvim_win_close, win, true)
            end
          end
        end
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_valid(buf) then
            local buf_name = vim.api.nvim_buf_get_name(buf)
            if buf_name == "" or not vim.api.nvim_get_option_value("buflisted", { buf = buf }) then
              pcall(vim.api.nvim_buf_delete, buf, { force = true })
            end
          end
        end
      ]])
    end,
  },
})

T["UI create_float Screenshots"]["Creates new buffer with content"] = function()
  child.lua([[
    local ui = require("codecompanion.utils.ui")

    local lines = {
      "-- This is a new buffer created by create_float",
      "local function example()",
      "  print('Hello from new buffer!')",
      "  return 42",
      "end",
      "",
      "example()"
    }

    local bufnr, winnr = ui.create_float(lines, {
      window = { width = 50, height = 10 },
      filetype = "lua",
      title = "New Buffer Test",
      show_dim = true,
    })

    -- Verify content was set
    local buffer_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert(#buffer_content == 7, "Buffer should have 7 lines")
    assert(buffer_content[1]:match("new buffer created"), "First line should mention new buffer")
  ]])

  local expect = MiniTest.expect
  expect.reference_screenshot(child.get_screenshot())
end

T["UI create_float Screenshots"]["Uses existing buffer without overwriting content"] = function()
  child.lua([[
    local ui = require("codecompanion.utils.ui")

    -- Create and populate an existing buffer
    local existing_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(existing_bufnr, 0, -1, false, {
      "-- This is EXISTING buffer content",
      "-- This should NOT be overwritten",
      "local existing_function = function()",
      "  return 'I already exist!'",
      "end"
    })
    vim.bo[existing_bufnr].filetype = "lua"

    -- Use create_float with existing buffer and overwrite_buffer = false
    local dummy_lines = {"This should not appear", "These lines ignored"}

    local bufnr, winnr = ui.create_float(dummy_lines, {
      bufnr = existing_bufnr,
      overwrite_buffer = false,
      relative = "editor",
      show_dim = true,
      title = "Existing Buffer Test",
      window = { width = 45, height = 8 },
    })

    -- Verify existing content was preserved
    local buffer_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert(buffer_content[1]:match("EXISTING buffer"), "Should preserve existing content")
    assert(not buffer_content[1]:match("should not appear"), "Should not have new content")
    assert(bufnr == existing_bufnr, "Should return the same buffer")
  ]])

  local expect = MiniTest.expect
  expect.reference_screenshot(child.get_screenshot())
end

T["UI create_float Screenshots"]["Uses existing buffer with content overwrite (debug.lua style)"] = function()
  child.lua([[
    local ui = require("codecompanion.utils.ui")

    -- Create an existing buffer (like debug.lua does)
    local existing_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(existing_bufnr, 0, -1, false, {
      "-- Old debug content",
      "-- This will be replaced"
    })

    -- New debug content to display
    local new_debug_lines = {
      "-- Updated Debug Information --",
      "Chat State: Active",
      "Messages: 5",
      "Last Response: 2024-01-15 10:30:00",
      "",
      "Adapter Details:",
      "  Name: gpt-4",
      "  Status: Connected",
      "  Tokens Used: 1,234",
      "",
      "Recent Activity:",
      "  → User message received",
      "  → Processing with LLM",
      "  → Response generated",
      "  → Display updated"
    }

    -- Use create_float with existing buffer (debug.lua pattern)
    local bufnr, winnr = ui.create_float(new_debug_lines, {
      bufnr = existing_bufnr,
      -- overwrite_buffer is not specified, so defaults to true
      window = { width = 55, height = 16 },
      relative = "editor",
      filetype = "lua",
      title = "Debug Chat Info",
      style = "minimal",
      show_dim = true,
    })

    -- Verify new content was set
    local buffer_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert(buffer_content[1]:match("Updated Debug"), "Should have new debug content")
    assert(not buffer_content[1]:match("Old debug"), "Should not have old content")
    assert(bufnr == existing_bufnr, "Should return the same buffer")
  ]])

  local expect = MiniTest.expect
  expect.reference_screenshot(child.get_screenshot())
end

return T
