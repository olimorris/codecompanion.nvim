local h = require("tests.helpers")
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        formatters = require("codecompanion.strategies.chat.acp.formatters")

        -- Mock adapter configurations
        mock_adapter_full = {
          opts = {
            trim_tool_output = false,
          },
        }

        mock_adapter_trimmed = {
          opts = {
            trim_tool_output = true,
          },
        }

        mock_adapter_no_opts = {}
      ]])
    end,
    post_once = child.stop,
  },
})

T["ACP Formatters"] = new_set()

-- Helper function to test tool messages
local function test_tool_message(tool_call, adapter, expected)
  child.lua("_G.test_tool_call = " .. vim.inspect(tool_call))
  child.lua("_G.test_adapter = " .. vim.inspect(adapter))
  local result = child.lua_get("formatters.tool_message(_G.test_tool_call, _G.test_adapter)")
  h.eq(expected, result)
end

T["ACP Formatters"]["extract_text"] = function()
  -- Test text content block with sanitization
  local result = child.lua_get([[formatters.extract_text({
    type = "text",
    text = "Hello\nWorld\n```lua\ncode\n```\nMore text",
  })]])
  h.eq("Hello World code More text", result)

  -- Test resource link
  result = child.lua_get([[formatters.extract_text({
    type = "resource_link",
    uri = "file:///path/to/file.txt",
  })]])
  h.eq("[resource: file:///path/to/file.txt]", result)

  -- Test image block
  result = child.lua_get([[formatters.extract_text({ type = "image" })]])
  h.eq("[image]", result)

  -- Test invalid input
  result = child.lua_get([[formatters.extract_text(nil)]])
  h.eq(vim.NIL, result)
end

T["ACP Formatters"]["short_title"] = function()
  -- Test with diff path
  local result = child.lua_get([[formatters.short_title({
    kind = "edit",
    title = "Write file",
    content = { { type = "diff", path = "/Users/test/project/file.lua" } },
  })]])
  h.eq("Edit: /Users/test/project/file.lua", result)

  -- Test with backtick command
  result = child.lua_get([[formatters.short_title({
    kind = "execute",
    title = "`ls -la /tmp`",
  })]])
  h.eq("Execute: `ls -la /tmp`", result)

  -- Test with quoted title
  result = child.lua_get([[formatters.short_title({
    kind = "fetch",
    title = '"Sheffield United"',
  })]])
  h.eq('Fetch: "Sheffield United"', result)
end

T["ACP Formatters"]["tool_message - Edit Tools"] = function()
  -- Test completed edit with diff
  test_tool_message({
    toolCallId = "edit123",
    title = "Write file.lua",
    kind = "edit",
    status = "completed",
    content = {
      {
        type = "diff",
        path = "/Users/test/file.lua",
        oldText = "old content",
        newText = "old content\nnew line",
      },
    },
    locations = { { path = "/Users/test/file.lua" } },
  }, { opts = { trim_tool_output = false } }, "Edited /Users/test/file.lua (+1 lines)")

  -- Test trimmed output
  test_tool_message({
    toolCallId = "edit123",
    title = "Write file.lua",
    kind = "edit",
    status = "completed",
    content = {
      {
        type = "diff",
        path = "/Users/test/file.lua",
        oldText = "old content",
        newText = "old content\nnew line",
      },
    },
    locations = { { path = "/Users/test/file.lua" } },
  }, { opts = { trim_tool_output = true } }, "Edit: /Users/test/file.lua")

  -- Test pending edit
  test_tool_message({
    toolCallId = "edit123",
    title = "Write file.lua",
    kind = "edit",
    status = "pending",
    locations = { { path = "/Users/test/file.lua" } },
  }, { opts = { trim_tool_output = false } }, "Edit: /Users/test/file.lua")
end

T["ACP Formatters"]["tool_message - Read Tools"] = function()
  -- Test completed read with content
  test_tool_message({
    toolCallId = "read123",
    title = "Read config.json",
    kind = "read",
    status = "completed",
    content = {
      {
        type = "content",
        content = {
          type = "text",
          text = '{"name": "test"}\n```json\nformatted\n```',
        },
      },
    },
    locations = { { path = "/Users/test/config.json" } },
  }, { opts = { trim_tool_output = false } }, 'Read: /Users/test/config.json — {"name": "test"} formatted')

  -- Test completed read without content
  test_tool_message({
    toolCallId = "read123",
    title = "Read config.json",
    kind = "read",
    status = "completed",
    content = {},
    locations = { { path = "/Users/test/config.json" } },
  }, { opts = { trim_tool_output = false } }, "Read: /Users/test/config.json")
end

T["ACP Formatters"]["tool_message - Real-world Examples"] = function()
  -- Test Claude Code edit example from JSON RPC
  test_tool_message({
    toolCallId = "toolu_01VRjmb5Vsv9WwwKu6cgH8a4",
    title = "Write /Users/Oli/Code/Neovim/codecompanion.nvim/quotes.lua",
    kind = "edit",
    status = "completed",
    content = {
      {
        type = "diff",
        path = "/Users/Oli/Code/Neovim/codecompanion.nvim/quotes.lua",
        oldText = nil,
        newText = "-- Simple test comment for ACP capture\nreturn {}\n",
      },
    },
    locations = {
      { path = "/Users/Oli/Code/Neovim/codecompanion.nvim/quotes.lua" },
    },
  }, { opts = { trim_tool_output = false } }, "Edited quotes.lua (+2 lines)")

  -- Test Claude Code execute example
  child.lua([[
    _G.claude_execute = {
      toolCallId = "toolu_017FaiLJGYNSVToDmZhrHqhA",
      title = "`ls -la lua/codecompanion/strategies/chat/acp/formatters/`",
      kind = "execute",
      status = "completed",
      content = {
        {
          type = "content",
          content = {
            type = "text",
            text = "total 56\ndrwxr-xr-x@ 6 Oli  staff    192  4 Nov 18:04 .\ndrwxr-xr-x@ 7 Oli  staff    224  4 Nov 18:05 ..\n-rw-r--r--@ 1 Oli  staff   4153  4 Nov 18:04 claude_code.lua",
          },
        },
      },
    }
    _G.result = formatters.tool_message(_G.claude_execute, mock_adapter_full)
  ]])
  local result = child.lua_get("_G.result")
  h.expect_truthy(result:match("^Execute: ls %-la lua/codecompanion/strategies/chat/acp/formatters/ — total 56"))
  h.expect_truthy(not result:match("\n"))

  -- Test Claude Code search example
  test_tool_message({
    toolCallId = "toolu_019YPt8kXTaoKTadxdQjfims",
    title = "Find `**/*add_buf_message*`",
    kind = "search",
    status = "completed",
    content = {
      {
        type = "content",
        content = {
          type = "text",
          text = "No files found",
        },
      },
    },
  }, { opts = { trim_tool_output = false } }, "Search: Find `**/*add_buf_message*` — No files found")
end

T["ACP Formatters"]["fs_write_message"] = function()
  -- Test normal file write
  local result = child.lua_get([[formatters.fs_write_message({
    path = "/Users/test/project/file.lua",
    bytes = 1024,
  })]])
  h.eq("Wrote 1024 bytes to /Users/test/project/file.lua", result)

  -- Test empty path
  result = child.lua_get([[formatters.fs_write_message({
    path = "",
    bytes = 1024,
  })]])
  h.eq("Wrote 1024 bytes to file", result)
end

return T
