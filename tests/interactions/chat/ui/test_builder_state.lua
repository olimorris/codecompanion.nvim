local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        config = require("tests.config")

        -- Fresh chat buffer
        _G.chat, _G.tools = h.setup_chat_buffer()
        _G.MT = _G.chat.MESSAGE_TYPES
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["Builder state"] = new_set()

T["Builder state"]["follows the block type through a section and re-anchors on a role change"] = function()
  child.lua([[
    _G.chat:add_buf_message({ role = "llm", content = "Intro" }, { type = _G.MT.LLM_MESSAGE })
  ]])
  local llm = child.lua_get([[_G.chat.builder.state]])
  h.eq(llm.last_role, "llm")
  h.eq(llm.block_type, "llm")
  h.not_eq(llm.current_section_start, nil)
  h.eq(llm.current_header_line > llm.current_section_start, true)

  child.lua([[
    _G.chat:add_buf_message({ role = "llm", content = "why step 1" }, { type = _G.MT.REASONING_MESSAGE })
    _G.chat:add_buf_message({ role = "llm", content = "why step 2" }, { type = _G.MT.REASONING_MESSAGE })
  ]])
  local reasoning = child.lua_get([[_G.chat.builder.state]])
  h.eq(reasoning.block_type, "reasoning")
  -- Same role, so the section anchors are untouched
  h.eq(reasoning.current_section_start, llm.current_section_start)
  h.eq(reasoning.current_header_line, llm.current_header_line)

  child.lua([[
    _G.chat:add_buf_message({ role = "llm", content = "Answer" }, { type = _G.MT.LLM_MESSAGE })
    _G.chat:add_buf_message({ role = "llm", content = "tool line 1\nline 2" }, { type = _G.MT.TOOL_MESSAGE })
  ]])
  h.eq(child.lua_get([[_G.chat.builder.state.block_type]]), "tool")

  child.lua([[
    _G.chat:add_buf_message({ role = "user", content = "Thanks" }, { type = _G.MT.USER_MESSAGE })
  ]])
  local user = child.lua_get([[_G.chat.builder.state]])
  h.eq(user.last_role, "user")
  h.eq(user.block_type, "llm")
  h.eq(user.current_section_start > llm.current_section_start, true)
  h.eq(user.current_header_line, user.current_section_start + 2)
end

T["Builder state"]["skips a stray empty chunk mid-section"] = function()
  child.lua([[
    _G.chat:add_buf_message({ role = "llm", content = "Intro" }, { type = _G.MT.LLM_MESSAGE })
  ]])
  local before = child.lua_get([[vim.api.nvim_buf_get_lines(_G.chat.bufnr, 0, -1, true)]])

  local insert_line = child.lua([[
    return _G.chat:add_buf_message({ role = "llm", content = "" }, { type = _G.MT.LLM_MESSAGE })
  ]])

  h.eq(insert_line, vim.NIL)
  h.eq(child.lua_get([[vim.api.nvim_buf_get_lines(_G.chat.bufnr, 0, -1, true)]]), before)
end

T["Builder"] = new_set()

T["Builder"]["a status write is collapsed onto a single line"] = function()
  child.lua([[
    _G.chat:add_buf_message(
      { role = "llm", content = "Execute: run tests\n\n  make test\n" },
      { type = _G.MT.TOOL_MESSAGE, status = "in_progress" }
    )
  ]])
  local lines = child.lua_get([[vim.api.nvim_buf_get_lines(_G.chat.bufnr, 0, -1, true)]])
  h.eq(lines[#lines], "Execute: run tests make test")
end

T["Builder"]["a tool write WITHOUT a status keeps its line breaks"] = function()
  child.lua([[
    _G.chat:add_buf_message({ role = "llm", content = "tool line 1\nline 2" }, { type = _G.MT.TOOL_MESSAGE })
  ]])
  local lines = child.lua_get([[vim.api.nvim_buf_get_lines(_G.chat.bufnr, 0, -1, true)]])
  h.eq(lines[#lines - 1], "tool line 1")
  h.eq(lines[#lines], "line 2")
end

T["Builder"]["update_line collapses a multi-line replacement rather than losing the write"] = function()
  local line_number = child.lua([[
    local line = _G.chat:add_buf_message(
      { role = "llm", content = "run_command: ls" },
      { type = _G.MT.TOOL_MESSAGE, status = "in_progress" }
    )
    return line
  ]])
  local before = child.lua_get([[vim.api.nvim_buf_line_count(_G.chat.bufnr)]])

  local updated = child.lua(
    [[return _G.chat:update_buf_line({ line_number = ..., content = "run_command: ls -la \\\n  --color", status = "success" })]],
    { line_number }
  )

  h.eq(updated, true)
  h.eq(child.lua_get([[vim.api.nvim_buf_line_count(_G.chat.bufnr)]]), before)
  h.eq(
    child.lua_get([[vim.api.nvim_buf_get_lines(_G.chat.bufnr, ... - 1, ..., true)]], { line_number }),
    { "run_command: ls -la \\ --color" }
  )
end

return T
