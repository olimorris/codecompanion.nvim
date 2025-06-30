local helpers = require("tests.helpers")
local h = helpers

local IterationManager = require("codecompanion.strategies.chat.iteration_manager")

local T = {}

-- Mock chat instance
local mock_chat = {
  id = 12345,
  bufnr = 1,
}

-- Mock vim.fn.confirm for testing
local confirm_responses = {}
local confirm_call_count = 0

_G.vim = _G.vim or {}
_G.vim.fn = _G.vim.fn or {}
_G.vim.fn.confirm = function(message, choices, default, type)
  confirm_call_count = confirm_call_count + 1
  local response = confirm_responses[confirm_call_count] or 1
  return response
end

T["IterationManager"] = {}

T["IterationManager"]["can be created with default config"] = function()
  local manager = IterationManager.new({
    chat = mock_chat,
  })

  h.eq("table", type(manager))
  h.eq(mock_chat, manager.chat)
  h.eq(0, manager.current_iterations)
  h.eq(20, manager.max_iterations) -- default value
end

T["IterationManager"]["can be created with custom config"] = function()
  local custom_config = {
    max_iterations_per_task = 15,
    iteration_increase_amount = 5,
    show_iteration_progress = false,
  }

  local manager = IterationManager.new({
    chat = mock_chat,
    config = custom_config,
  })

  h.eq(15, manager.max_iterations)
  h.eq(5, manager.config.iteration_increase_amount)
  h.eq(false, manager.config.show_iteration_progress)
end

T["IterationManager"]["starts task correctly"] = function()
  local manager = IterationManager.new({
    chat = mock_chat,
  })

  manager:start_task("Test task")

  h.eq(0, manager.current_iterations)
  h.eq(1, #manager.iteration_history)
  h.eq("task_start", manager.iteration_history[1].type)
  h.eq("Test task", manager.iteration_history[1].description)
end

T["IterationManager"]["increments and checks iterations"] = function()
  local manager = IterationManager.new({
    chat = mock_chat,
    config = { max_iterations_per_task = 3 },
  })

  -- First iterations should be allowed
  local continue1, reason1 = manager:increment_and_check("test_iteration")
  h.eq(true, continue1)
  h.eq(nil, reason1)
  h.eq(1, manager.current_iterations)

  local continue2, reason2 = manager:increment_and_check("test_iteration")
  h.eq(true, continue2)
  h.eq(nil, reason2)
  h.eq(2, manager.current_iterations)

  local continue3, reason3 = manager:increment_and_check("test_iteration")
  h.eq(true, continue3)
  h.eq(nil, reason3)
  h.eq(3, manager.current_iterations)
end

T["IterationManager"]["blocks iterations when limit reached and user cancels"] = function()
  confirm_responses = { 2 } -- User selects "Cancel"
  confirm_call_count = 0

  local manager = IterationManager.new({
    chat = mock_chat,
    config = { max_iterations_per_task = 2 },
  })

  -- Reach the limit
  manager:increment_and_check("test_iteration")
  manager:increment_and_check("test_iteration")

  -- This should trigger user confirmation and block
  local continue, reason = manager:increment_and_check("test_iteration")
  h.eq(false, continue)
  h.match("User cancelled", reason)
  h.eq(3, manager.current_iterations) -- Still incremented before checking
end

T["IterationManager"]["allows continuation when user approves"] = function()
  confirm_responses = { 1 } -- User selects "Continue"
  confirm_call_count = 0

  local manager = IterationManager.new({
    chat = mock_chat,
    config = {
      max_iterations_per_task = 2,
      iteration_increase_amount = 5,
    },
  })

  -- Reach the limit
  manager:increment_and_check("test_iteration")
  manager:increment_and_check("test_iteration")

  -- This should trigger user confirmation and allow continuation
  local continue, reason = manager:increment_and_check("test_iteration")
  h.eq(true, continue)
  h.eq(nil, reason)
  h.eq(7, manager.max_iterations) -- 2 + 5 = 7
  h.eq(3, manager.current_iterations)
end

T["IterationManager"]["tracks iteration history"] = function()
  local manager = IterationManager.new({
    chat = mock_chat,
  })

  manager:start_task("Test task")
  manager:increment_and_check("llm_request")
  manager:increment_and_check("tool_execution")

  h.eq(3, #manager.iteration_history)
  h.eq("task_start", manager.iteration_history[1].type)
  h.eq("llm_request", manager.iteration_history[2].type)
  h.eq("tool_execution", manager.iteration_history[3].type)
end

T["IterationManager"]["formats iteration summary"] = function()
  local manager = IterationManager.new({
    chat = mock_chat,
  })

  manager:start_task("Test task")
  manager:increment_and_check("llm_request")
  manager:increment_and_check("llm_request")
  manager:increment_and_check("tool_execution")

  local summary = manager:format_iteration_summary()
  h.match("llm_request: 2 times", summary)
  h.match("tool_execution: 1 times", summary)
end

T["IterationManager"]["reports status correctly"] = function()
  local manager = IterationManager.new({
    chat = mock_chat,
    config = { max_iterations_per_task = 5 },
  })

  manager:increment_and_check("test")
  manager:increment_and_check("test")

  local status = manager:get_status()
  h.eq(2, status.current_iterations)
  h.eq(5, status.max_iterations)
  h.eq(3, status.iterations_remaining)
  h.eq("table", type(status.iteration_history))
end

T["IterationManager"]["detects approaching limit"] = function()
  local manager = IterationManager.new({
    chat = mock_chat,
    config = { max_iterations_per_task = 10 },
  })

  -- At 7/10 iterations (70%), should not be approaching with default 80% threshold
  for i = 1, 7 do
    manager:increment_and_check("test")
  end
  h.eq(false, manager:is_approaching_limit())

  -- At 8/10 iterations (80%), should be approaching with default 80% threshold
  manager:increment_and_check("test")
  h.eq(true, manager:is_approaching_limit())

  -- Test custom threshold
  manager.current_iterations = 7
  h.eq(true, manager:is_approaching_limit(0.7)) -- 70% threshold
end

T["IterationManager"]["resets correctly"] = function()
  local manager = IterationManager.new({
    chat = mock_chat,
  })

  manager:start_task("Test task")
  manager:increment_and_check("test")
  manager:increment_and_check("test")

  h.eq(2, manager.current_iterations)
  h.eq(3, #manager.iteration_history) -- task_start + 2 iterations

  manager:reset()

  h.eq(0, manager.current_iterations)
  h.eq(0, #manager.iteration_history)
end

T["IterationManager"]["sets max iterations"] = function()
  local manager = IterationManager.new({
    chat = mock_chat,
    config = { max_iterations_per_task = 10 },
  })

  h.eq(10, manager.max_iterations)

  manager:set_max_iterations(25)

  h.eq(25, manager.max_iterations)
  -- Should record the change in history
  h.eq(1, #manager.iteration_history)
  h.eq("limit_changed", manager.iteration_history[1].type)
  h.eq(10, manager.iteration_history[1].old_limit)
  h.eq(25, manager.iteration_history[1].new_limit)
end

T["IterationManager"]["exports history"] = function()
  local manager = IterationManager.new({
    chat = mock_chat,
  })

  manager:start_task("Test task")
  manager:increment_and_check("test")

  local exported = manager:export_history()

  h.eq("table", type(exported))
  h.eq("table", type(exported.config))
  h.eq(1, exported.current_iterations)
  h.eq("table", type(exported.history))
  h.eq("number", type(exported.export_timestamp))
end

T["IterationManager"]["handles empty iteration history"] = function()
  local manager = IterationManager.new({
    chat = mock_chat,
  })

  local summary = manager:format_iteration_summary()
  h.eq("No iteration history available", summary)
end

return T
