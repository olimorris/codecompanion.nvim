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

T["Builder state"]["tracks formatter cache"] = function()
  local ids = child.lua([[
    local f = _G.chat.builder._formatters
    return { tostring(f[1]), tostring(f[2]), tostring(f[3]) }
  ]])

  -- Trigger a render to ensure reuse
  child.lua([[
    _G.chat:add_buf_message({ role = "llm", content = "Hello" }, { type = _G.MT.LLM_MESSAGE })
  ]])

  local ids2 = child.lua([[
    local f = _G.chat.builder._formatters
    return { tostring(f[1]), tostring(f[2]), tostring(f[3]) }
  ]])

  h.eq(ids, ids2)
end

T["Builder state"]["updates blocks, sections, reasoning flag, and write bounds"] = function()
  -- 1) Start with an LLM message (new section, first block)
  child.lua([[
    _G.chat:add_buf_message({ role = "llm", content = "Intro" }, { type = _G.MT.LLM_MESSAGE })
  ]])

  local s1 = child.lua_get([[_G.chat.builder.state]])
  -- Section started
  h.not_eq(s1.section_index, 0)
  h.eq(s1.block_index, 1)
  h.eq(s1.current_block_type, "llm_message")
  h.eq(s1.chunks_in_block, 1)

  h.not_eq(s1.current_section_start, nil)
  h.not_eq(s1.last_write_start, nil)
  h.not_eq(s1.last_write_end, nil)
  h.not_eq(s1.last_write_end < s1.last_write_start, true) -- should not be descending

  -- 2) Reasoning block (new block, has_reasoning_output = true)
  child.lua([[
    _G.chat:add_buf_message({ role = "llm", content = "why step 1" }, { type = _G.MT.REASONING_MESSAGE })
  ]])
  local s2 = child.lua_get([[_G.chat.builder.state]])
  h.eq(s2.has_reasoning_output, true)
  h.eq(s2.current_block_type, "reasoning_message")
  h.eq(s2.block_index, 2)
  h.eq(s2.chunks_in_block, 1)
  h.not_eq(s2.last_write_start < s1.last_write_start, true) -- moved forward (likely)

  -- 3) Another reasoning chunk (same block, chunks_in_block increments)
  child.lua([[
    _G.chat:add_buf_message({ role = "llm", content = "why step 2" }, { type = _G.MT.REASONING_MESSAGE })
  ]])
  local s3 = child.lua_get([[_G.chat.builder.state]])
  h.eq(s3.has_reasoning_output, true)
  h.eq(s3.current_block_type, "reasoning_message")
  h.eq(s3.block_index, 2) -- same block
  h.eq(s3.chunks_in_block, 2) -- incremented chunk count

  -- 4) Transition back to LLM message (Standard adds "### Response", clears reasoning)
  child.lua([[
    _G.chat:add_buf_message({ role = "llm", content = "Answer" }, { type = _G.MT.LLM_MESSAGE })
  ]])
  local s4 = child.lua_get([[_G.chat.builder.state]])
  h.eq(s4.has_reasoning_output, false)
  h.eq(s4.current_block_type, "llm_message")
  h.eq(s4.block_index, 3)
  h.eq(s4.chunks_in_block, 1)
  h.not_eq(s4.last_write_start < s3.last_write_start, true)

  -- 5) Tool output (multi-line) → new block
  child.lua([[
    _G.chat:add_buf_message({ role = "llm", content = "tool line 1\nline 2" }, { type = _G.MT.TOOL_MESSAGE })
  ]])
  local s5 = child.lua_get([[_G.chat.builder.state]])
  h.eq(s5.current_block_type, "tool_message")
  h.eq(s5.block_index, 4)
  h.eq(s5.chunks_in_block, 1)

  -- 6) User message → new section (role change), section anchors updated
  child.lua([[
    _G.chat:add_buf_message({ role = "user", content = "Thanks" }, { type = _G.MT.USER_MESSAGE })
  ]])
  local s6 = child.lua_get([[_G.chat.builder.state]])

  -- Role change should have advanced section index and set section anchors
  h.not_eq(s6.section_index, s5.section_index)
  h.not_eq(s6.current_section_start, nil)

  -- last_section_start should be populated after at least two sections
  h.not_eq(s6.last_section_start, nil)

  -- Optional: sanity check ordering of section anchors
  h.eq(s6.last_section_start < s6.current_section_start, true)
end

T["Builder state"]["_should_start_new_block is based on type change"] = function()
  child.lua([[
    -- First LLM message
    _G.chat:add_buf_message({ role = "llm", content = "A" }, { type = _G.MT.LLM_MESSAGE })
    -- Same type → same block, chunks_in_block increments
    _G.chat:add_buf_message({ role = "llm", content = "B" }, { type = _G.MT.LLM_MESSAGE })
  ]])

  local sA = child.lua_get([[_G.chat.builder.state]])
  h.eq(sA.current_block_type, "llm_message")
  h.eq(sA.block_index, 1)
  h.eq(sA.chunks_in_block, 2)

  child.lua([[
    -- Different type → new block
    _G.chat:add_buf_message({ role = "llm", content = "reason" }, { type = _G.MT.REASONING_MESSAGE })
  ]])

  local sB = child.lua_get([[_G.chat.builder.state]])
  h.eq(sB.current_block_type, "reasoning_message")
  h.eq(sB.block_index, 2)
  h.eq(sB.chunks_in_block, 1)
end

return T
