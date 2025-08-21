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

T["UI Spacing Refactor"]["reduced spacing between LLM and tool messages"] = function()
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
    
    -- Find the position of LLM message and tool message
    local llm_line_idx = nil
    local tool_line_idx = nil
    for i, line in ipairs(lines) do
      if line:match("I'll help you with that") then
        llm_line_idx = i
      elseif line:match("Tool executed successfully") then
        tool_line_idx = i
      end
    end

    -- Count empty lines between LLM and tool message
    local empty_lines_between = 0
    if llm_line_idx and tool_line_idx then
      for i = llm_line_idx + 1, tool_line_idx - 1 do
        if lines[i] == "" then
          empty_lines_between = empty_lines_between + 1
        end
      end
    end

    return {
      buffer_lines = lines,
      llm_line_idx = llm_line_idx,
      tool_line_idx = tool_line_idx,
      empty_lines_between = empty_lines_between
    }
  ]])

  -- Should have at most 1 empty line between LLM message and tool output (improved from before)
  h.leq(result.empty_lines_between, 1)
  h.neq(result.llm_line_idx, nil) -- Should find LLM message
  h.neq(result.tool_line_idx, nil) -- Should find tool message
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
    
    -- Check for reasoning header and response header
    local has_reasoning_header = false
    local has_response_header = false
    local response_header_line = nil
    for i, line in ipairs(lines) do
      if line:match("### Reasoning") then
        has_reasoning_header = true
      elseif line:match("### Response") then
        has_response_header = true
        response_header_line = i
      end
    end

    return {
      buffer_lines = lines,
      has_reasoning_header = has_reasoning_header,
      has_response_header = has_response_header,
      response_header_line = response_header_line
    }
  ]])

  h.eq(result.has_reasoning_header, true)
  h.eq(result.has_response_header, true)
  h.neq(result.response_header_line, nil)
end

T["UI Spacing Refactor"]["tool output has proper trailing spacing for folding"] = function()
  local result = child.lua([[
    -- Add tool output
    _G.chat.builder:add_message({
      role = "llm",
      content = "Tool executed successfully\\nWith multiple lines\\nOf output"
    }, { type = _G.chat.MESSAGE_TYPES.TOOL_MESSAGE })

    local lines = h.get_buf_lines(_G.chat.bufnr)
    
    -- Find the last line of tool content
    local last_content_line_idx = nil
    for i = #lines, 1, -1 do
      if lines[i]:match("Of output") then
        last_content_line_idx = i
        break
      end
    end

    -- Check if there's a trailing empty line after tool content
    local has_trailing_empty = false
    if last_content_line_idx and last_content_line_idx < #lines then
      has_trailing_empty = lines[last_content_line_idx + 1] == ""
    end

    return {
      buffer_lines = lines,
      last_content_line_idx = last_content_line_idx,
      has_trailing_empty = has_trailing_empty
    }
  ]])

  h.neq(result.last_content_line_idx, nil) -- Should find tool content
  h.eq(result.has_trailing_empty, true) -- Should have trailing empty line for folding
end

return T