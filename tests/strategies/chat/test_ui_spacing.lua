local h = require("tests.helpers")

local expect = MiniTest.expect
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        _G.chat, _G.tools = h.setup_chat_buffer()
      ]])
    end,
    post_case = function()
      child.lua([[
        _G.chat = nil
        _G.tools = nil
      ]])
    end,
    post_once = child.stop,
  },
})

T["UI Spacing Refactor"] = new_set()

T["UI Spacing Refactor"]["basic tool output has reduced spacing"] = function()
  local result = child.lua([[
    -- Add a user message first
    _G.chat.builder:add_message({
      role = "user",
      content = "Test message"
    }, {})

    -- Add LLM response
    _G.chat.builder:add_message({
      role = "llm", 
      content = "I'll help you with that."
    }, { type = _G.chat.MESSAGE_TYPES.LLM_MESSAGE })

    -- Add tool output
    _G.chat.builder:add_message({
      role = "llm",
      content = "Tool executed successfully"
    }, { type = _G.chat.MESSAGE_TYPES.TOOL_MESSAGE })

    local lines = h.get_buf_lines(_G.chat.bufnr)
    
    -- Count consecutive empty lines after tool output
    local consecutive_empty = 0
    local max_consecutive_empty = 0
    for i, line in ipairs(lines) do
      if line == "" then
        consecutive_empty = consecutive_empty + 1
        max_consecutive_empty = math.max(max_consecutive_empty, consecutive_empty)
      else
        consecutive_empty = 0
      end
    end

    return {
      buffer_lines = lines,
      max_consecutive_empty = max_consecutive_empty,
      total_lines = #lines
    }
  ]])

  -- Should have significantly fewer consecutive empty lines
  h.leq(result.max_consecutive_empty, 2) -- At most 2 consecutive empty lines
  h.neq(result.total_lines, 0) -- Should have content
end

T["UI Spacing Refactor"]["reasoning to response transition works"] = function()
  local result = child.lua([[
    -- Add reasoning output
    _G.chat.builder:add_message({
      role = "llm",
      content = "Let me think about this..."
    }, { type = _G.chat.MESSAGE_TYPES.REASONING_MESSAGE })

    -- Add more reasoning
    _G.chat.builder:add_message({
      role = "llm", 
      content = "This requires careful consideration."
    }, { type = _G.chat.MESSAGE_TYPES.REASONING_MESSAGE })

    -- Add standard response
    _G.chat.builder:add_message({
      role = "llm",
      content = "Here's my answer."
    }, { type = _G.chat.MESSAGE_TYPES.LLM_MESSAGE })

    local lines = h.get_buf_lines(_G.chat.bufnr)
    
    -- Check for reasoning header
    local has_reasoning_header = false
    local has_response_header = false
    for _, line in ipairs(lines) do
      if line:match("### Reasoning") then
        has_reasoning_header = true
      elseif line:match("### Response") then
        has_response_header = true
      end
    end

    return {
      buffer_lines = lines,
      has_reasoning_header = has_reasoning_header,
      has_response_header = has_response_header
    }
  ]])

  h.eq(result.has_reasoning_header, true)
  h.eq(result.has_response_header, true)
end

return T