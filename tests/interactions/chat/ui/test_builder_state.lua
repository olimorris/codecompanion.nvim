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

T["Builder state"]["tool fold is placed on the content line when the tool message creates the header"] = function()
  -- Mirrors adapters (e.g. OpenRouter) that emit a tool call with no rendered
  -- text first, so the tool output is the message that renders the LLM header.
  -- The fold must sit on the tool content, not back up in the user's section.
  child.lua([[
    require("codecompanion.config").interactions.chat.tools.opts.folds.enabled = true

    _G.chat:add_buf_message(
      { role = "llm", content = "tool line 1\ntool line 2\ntool line 3" },
      { type = _G.MT.TOOL_MESSAGE }
    )
    vim.wait(200, function() return false end)
  ]])

  local res = child.lua([[
    local bufnr = _G.chat.bufnr
    local folds = require("codecompanion.interactions.chat.ui.folds").fold_summaries[bufnr] or {}
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)

    local content_row0 = nil
    for i, l in ipairs(lines) do
      if l == "tool line 1" then
        content_row0 = i - 1
        break
      end
    end

    return { content_row0 = content_row0, fold = content_row0 and folds[content_row0] or nil }
  ]])

  h.not_eq(res.content_row0, nil, "Expected to find the tool content in the buffer")
  h.not_eq(res.fold, nil, "Expected a tool fold keyed on the content line")
  h.eq(res.fold.type, "tool")
end

return T
