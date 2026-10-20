local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")

        _G.chat = h.setup_chat_buffer({}, {
          name = "test_acp",
          config = { name = "test_acp", type = "acp", handlers = { form_messages = function(a, m) return m end } },
        })
        local handler = require("codecompanion.interactions.chat.acp.handler").new(_G.chat)
        handler:process_tool_call({ toolCallId = "1", status = "in_progress", kind = "read", title = "Read file.lua", rawInput = { path = "file.lua" } })
        handler:process_tool_call({ toolCallId = "1", status = "completed" })

        _G.show_tool_call_on = function(row)
          vim.api.nvim_set_current_win(_G.chat.ui.winnr)
          vim.api.nvim_win_set_cursor(0, { row, 0 })
          require("codecompanion.interactions.chat.ui.tool_calls").show(_G.chat)
          for _, winnr in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.api.nvim_win_get_config(winnr).relative ~= "" then
              return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(winnr), 0, -1, false)
            end
          end
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["Tool Calls"] = new_set()

T["Tool Calls"]["opens a tool call after its line is updated"] = function()
  local lines = child.lua([[
    vim.api.nvim_set_current_win(_G.chat.ui.winnr)
    local row = vim.fn.search("file.lua", "n")
    return _G.show_tool_call_on(row)
  ]])

  h.eq({ "**path**", "````", "file.lua", "````" }, lines)
end

T["Tool Calls"]["DOES NOT open a stale tool call after the buffer is re-rendered"] = function()
  local lines = child.lua([[
    _G.chat.ui:render(_G.chat.buffer_context, _G.chat.messages, _G.chat.opts)
    return _G.show_tool_call_on(1)
  ]])

  h.eq(vim.NIL, lines)
end

T["Tool Calls"]["opens an HTTP tool call after compaction removes it from the messages"] = function()
  local lines = child.lua([[
    _G.chat, _G.tools = h.setup_chat_buffer()
    _G.tools:execute(_G.chat, {
      { id = "call_1", type = "function", ["function"] = { name = "weather", arguments = { location = "London, UK", units = "celsius" } } },
    })
    _G.chat.messages = {}

    vim.api.nvim_set_current_win(_G.chat.ui.winnr)
    return _G.show_tool_call_on(vim.fn.search("Weather", "n"))
  ]])

  h.eq({
    "**location**",
    "````",
    "London, UK",
    "````",
    "",
    "**units**",
    "````",
    "celsius",
    "````",
    "──────────────────────────────────────",
    "````",
    "Ran the weather tool The weather in London, UK is 15° celsius",
    "````",
  }, lines)
end

T["Tool Calls"]["shows the diff of an ACP edit that has no output"] = function()
  local lines = child.lua([[
    local handler = require("codecompanion.interactions.chat.acp.handler").new(_G.chat)
    handler:process_tool_call({
      toolCallId = "2",
      status = "completed",
      kind = "edit",
      title = "Edit new.lua",
      content = { { type = "diff", path = "new.lua", oldText = vim.NIL, newText = "local x = 1" } },
    })

    vim.api.nvim_set_current_win(_G.chat.ui.winnr)
    return _G.show_tool_call_on(vim.fn.search("new.lua", "n"))
  ]])

  h.eq({
    "Edit new.lua",
    "─────────────",
    "````diff",
    "--- new.lua",
    "+++ new.lua",
    "@@ -0,0 +1 @@",
    "+local x = 1",
    "````",
  }, lines)
end

T["Tool Calls"]["escapes markdown in a summary rather than removing it"] = function()
  local summary = child.lua([[
    return require("codecompanion.interactions.chat.ui.tool_calls").format_summary({
      kind = "run_command",
      detail = "ls ~/src/*.lua C:\\src",
    })
  ]])

  h.eq("**Run command** ls \\~/src/\\*.lua C:\\\\src", summary)
end

return T
