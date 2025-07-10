local config = require("tests.config")
local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
				_G.chat = h.setup_chat_buffer()
      ]])
    end,
    post_case = function()
      child.lua([[
        _G.chat = nil
      ]])
    end,
    post_once = child.stop,
  },
})

T["Builder"] = new_set()
T["Builder"]["State management"] = new_set()

T["Builder"]["State management"]["persists last_role across calls"] = function()
  local result = child.lua([[

    -- Initial state should have user role
    local initial_role = _G.chat.builder.state.last_role

    -- Add an LLM message
    _G.chat.builder:add_message({
      role = "llm",
      content = "Hello there"
    }, {})

    -- State should now have llm role
    local after_llm_role = _G.chat.builder.state.last_role

    -- Chat object should also be synced
    local chat_role = _G.chat._last_role

    return {
      initial = initial_role,
      after_llm = after_llm_role,
      chat_synced = chat_role
    }
  ]])

  -- Verify state transitions work correctly
  h.eq(result.initial, "user")
  h.eq(result.after_llm, "llm")
  h.eq(result.chat_synced, "llm") -- Builder synced back to chat
end

T["Builder"]["Sections"] = new_set()

T["Builder"]["Sections"]["detects new section for tool output after LLM message"] = function()
  local result = child.lua([[
    -- First add an LLM message to set the state
    _G.chat.builder:add_message({
      role = "llm",
      content = "I'll help you with that."
}, { type = _G.chat.MESSAGE_TYPES.LLM_MESSAGE })

    local last_type = _G.chat.builder.state.last_type

    -- Now add tool output - this should trigger new section detection
    _G.chat.builder:add_message({
      role = "llm",
      content = "Tool executed successfully"
}, { type = _G.chat.MESSAGE_TYPES.TOOL_MESSAGE })

    -- Get the buffer contents to see if formatting worked
    local lines = h.get_buf_lines(_G.chat.bufnr)

    return {
      first_type = last_type,
      final_type = _G.chat.builder.state.last_type,
      buffer_lines = lines,

      -- Let's also check some internal logic
      should_start_new_section = _G.chat.builder:_should_start_new_section(
        { type = _G.chat.MESSAGE_TYPES.TOOL_MESSAGE },
        { last_type = _G.chat.MESSAGE_TYPES.LLM_MESSAGE }
      )
    }
  ]])

  -- Verify the type transition logic
  h.eq(result.first_type, child.lua("return _G.chat.MESSAGE_TYPES.LLM_MESSAGE"))
  h.eq(result.final_type, child.lua("return _G.chat.MESSAGE_TYPES.TOOL_MESSAGE"))
  h.eq(result.should_start_new_section, true)
end

T["Builder"]["Reasoning"] = new_set()

T["Builder"]["Reasoning"]["manages reasoning to response transition"] = function()
  local result = child.lua([[
    -- Add reasoning content first
    _G.chat.builder:add_message({
      role = "llm",
      content = "Let me think about this..."
    }, { type = _G.chat.MESSAGE_TYPES.REASONING_MESSAGE })

    local after_reasoning_state = _G.chat.builder.state.has_reasoning_output

    -- Add response content - should transition from reasoning
    _G.chat.builder:add_message({
      role = "llm",
      content = "Here's my answer"
    }, {})

    local after_response_state = _G.chat.builder.state.has_reasoning_output
    local lines = h.get_buf_lines(_G.chat.bufnr)

    return {
      after_reasoning = after_reasoning_state,
      after_response = after_response_state,
      buffer_lines = lines
    }
  ]])

  -- Verify reasoning state management
  h.eq(result.after_reasoning, true) -- Reasoning should set flag to true
  h.eq(result.after_response, false) -- Response should reset flag to false

  -- Verify both headers appeared
  local has_reasoning_header = false
  local has_response_header = false
  for _, line in ipairs(result.buffer_lines) do
    if line:match("### Reasoning") then
      has_reasoning_header = true
    elseif line:match("### Response") then
      has_response_header = true
    end
  end
  h.eq(has_reasoning_header, true)
  h.eq(has_response_header, true)
end

T["Builder"]["Headers"] = new_set()

T["Builder"]["Headers"]["adds headers on role changes"] = function()
  local result = child.lua([[
    -- Start with user message (should already be there from setup)
    local initial_role = _G.chat.builder.state.last_role

    -- Add LLM message - should trigger header
    _G.chat.builder:add_message({
      role = "llm",
      content = "Hello back!"
    }, {})

    -- Add another LLM message - should NOT trigger header
    _G.chat.builder:add_message({
      role = "llm",
      content = "More content"
    }, {})

    local lines = h.get_buf_lines(_G.chat.bufnr)

    return {
      initial_role = initial_role,
      final_role = _G.chat.builder.state.last_role,
      buffer_lines = lines
    }
  ]])

  h.eq(result.initial_role, "user")
  h.eq(result.final_role, "llm")

  -- Count LLM headers - should only be one
  local llm_header_count = 0
  for _, line in ipairs(result.buffer_lines) do
    if line:match("^## " .. config.strategies.chat.roles.llm) then
      llm_header_count = llm_header_count + 1
    end
  end
  h.eq(llm_header_count, 1) -- Should only add header once for role change
end

return T
