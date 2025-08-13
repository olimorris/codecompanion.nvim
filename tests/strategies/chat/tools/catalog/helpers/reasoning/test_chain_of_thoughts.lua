local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        ChainOfThoughts = require('codecompanion.strategies.chat.tools.catalog.helpers.reasoning.chain_of_thoughts')
      ]])
    end,
    post_once = child.stop,
  },
})

-- Test module initialization
T["can create new ChainOfThoughts instance"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
  ]])

  local problem = child.lua_get("cot.problem")
  local steps = child.lua_get("cot.steps")
  local current_step = child.lua_get("cot.current_step")

  h.eq("Test problem", problem)
  h.eq(0, #steps)
  h.eq(0, current_step)
end

T["can create ChainOfThoughts with empty problem"] = function()
  child.lua([[
    cot = ChainOfThoughts.new()
  ]])

  local problem = child.lua_get("cot.problem")
  h.eq("", problem)
end

-- Test step addition with valid types
T["can add analysis step"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    success, message = cot:add_step("analysis", "Analyze the problem", "Breaking down requirements", "step1")
  ]])

  local success = child.lua_get("success")
  local message = child.lua_get("message")
  local steps = child.lua_get("cot.steps")
  local current_step = child.lua_get("cot.current_step")

  h.eq(true, success)
  h.eq("Step added successfully", message)
  h.eq(1, #steps)
  h.eq(1, current_step)
  h.eq("analysis", steps[1].type)
  h.eq("Analyze the problem", steps[1].content)
  h.eq("Breaking down requirements", steps[1].reasoning)
  h.eq("step1", steps[1].id)
  h.eq(1, steps[1].step_number)
end

T["can add reasoning step"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    success, message = cot:add_step("reasoning", "Logical deduction", "Using inference", "step1")
  ]])

  local success = child.lua_get("success")
  local steps = child.lua_get("cot.steps")

  h.eq(true, success)
  h.eq("reasoning", steps[1].type)
end

T["can add task step"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    success, message = cot:add_step("task", "Implement solution", "Code the feature", "step1")
  ]])

  local success = child.lua_get("success")
  local steps = child.lua_get("cot.steps")

  h.eq(true, success)
  h.eq("task", steps[1].type)
end

T["can add validation step"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    success, message = cot:add_step("validation", "Test solution", "Verify correctness", "step1")
  ]])

  local success = child.lua_get("success")
  local steps = child.lua_get("cot.steps")

  h.eq(true, success)
  h.eq("validation", steps[1].type)
end

T["can add step without reasoning"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    success, message = cot:add_step("analysis", "Simple analysis", nil, "step1")
  ]])

  local success = child.lua_get("success")
  local steps = child.lua_get("cot.steps")

  h.eq(true, success)
  h.eq("", steps[1].reasoning)
end

T["can add multiple steps"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    cot:add_step("analysis", "First step", "Reasoning 1", "step1")
    cot:add_step("reasoning", "Second step", "Reasoning 2", "step2")
    cot:add_step("task", "Third step", "Reasoning 3", "step3")
  ]])

  local steps = child.lua_get("cot.steps")
  local current_step = child.lua_get("cot.current_step")

  h.eq(3, #steps)
  h.eq(3, current_step)
  h.eq(1, steps[1].step_number)
  h.eq(2, steps[2].step_number)
  h.eq(3, steps[3].step_number)
end

-- Test step validation errors
T["rejects invalid step type"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    success, message = cot:add_step("invalid", "Content", "Reasoning", "step1")
  ]])

  local success = child.lua_get("success")
  local message = child.lua_get("message")
  local steps = child.lua_get("cot.steps")

  h.eq(false, success)
  h.expect_contains("Invalid step type", message)
  h.eq(0, #steps)
end

T["rejects empty content"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    success, message = cot:add_step("analysis", "", "Reasoning", "step1")
  ]])

  local success = child.lua_get("success")
  local message = child.lua_get("message")

  h.eq(false, success)
  h.eq("Step content cannot be empty", message)
end

T["rejects nil content"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    success, message = cot:add_step("analysis", nil, "Reasoning", "step1")
  ]])

  local success = child.lua_get("success")
  local message = child.lua_get("message")

  h.eq(false, success)
  h.eq("Step content cannot be empty", message)
end

T["rejects empty step_id"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    success, message = cot:add_step("analysis", "Content", "Reasoning", "")
  ]])

  local success = child.lua_get("success")
  local message = child.lua_get("message")

  h.eq(false, success)
  h.eq("Step ID cannot be empty", message)
end

T["rejects nil step_id"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    success, message = cot:add_step("analysis", "Content", "Reasoning", nil)
  ]])

  local success = child.lua_get("success")
  local message = child.lua_get("message")

  h.eq(false, success)
  h.eq("Step ID cannot be empty", message)
end

-- Test step structure
T["creates step with correct structure"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    cot:add_step("analysis", "Test content", "Test reasoning", "test_id")
    step = cot.steps[1]
  ]])

  local step = child.lua_get("step")

  h.eq("test_id", step.id)
  h.eq("analysis", step.type)
  h.eq("Test content", step.content)
  h.eq("Test reasoning", step.reasoning)
  h.eq(1, step.step_number)
  h.eq("number", type(step.timestamp))
end

-- Test reflection on empty chain
T["reflects on empty chain"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    reflection = cot:reflect()
  ]])

  local reflection = child.lua_get("reflection")

  h.eq(0, reflection.total_steps)
  h.eq(1, #reflection.insights)
  h.eq("No steps to analyze", reflection.insights[1])
  h.eq(1, #reflection.improvements)
  h.eq("Add reasoning steps to begin analysis", reflection.improvements[1])
end

-- Test reflection with single step types
T["reflects on analysis-only chain"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    cot:add_step("analysis", "Analyze", "Detail", "step1")
    reflection = cot:reflect()
  ]])

  local reflection = child.lua_get("reflection")

  h.eq(1, reflection.total_steps)
  h.expect_contains("analysis:1", table.concat(reflection.insights, " "))
  h.expect_contains("reasoning steps", table.concat(reflection.improvements, " "))
  h.expect_contains("task steps", table.concat(reflection.improvements, " "))
end

T["reflects on reasoning-only chain"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    cot:add_step("reasoning", "Reason", "Detail", "step1")
    reflection = cot:reflect()
  ]])

  local reflection = child.lua_get("reflection")

  h.expect_contains("reasoning:1", table.concat(reflection.insights, " "))
  h.expect_contains("analysis steps", table.concat(reflection.improvements, " "))
  h.expect_contains("task steps", table.concat(reflection.improvements, " "))
end

-- Test reflection with good progression
T["reflects on well-structured chain"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    cot:add_step("analysis", "Analyze", "Detailed analysis", "step1")
    cot:add_step("reasoning", "Reason", "Logical deduction", "step2")
    cot:add_step("task", "Implement", "Code solution", "step3")
    reflection = cot:reflect()
  ]])

  local reflection = child.lua_get("reflection")

  h.eq(3, reflection.total_steps)
  h.expect_contains("Good logical progression", table.concat(reflection.insights, " "))
  h.expect_contains("validation steps", table.concat(reflection.improvements, " "))
end

T["reflects on complete chain with validation"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    cot:add_step("analysis", "Analyze", "Detailed analysis", "step1")
    cot:add_step("reasoning", "Reason", "Logical deduction", "step2")
    cot:add_step("task", "Implement", "Code solution", "step3")
    cot:add_step("validation", "Test", "Verify solution", "step4")
    reflection = cot:reflect()
  ]])

  local reflection = child.lua_get("reflection")

  h.eq(4, reflection.total_steps)
  h.expect_contains("Good logical progression", table.concat(reflection.insights, " "))
  -- Should not suggest validation steps since we have them
  local improvements_text = table.concat(reflection.improvements, " ")
  h.eq(nil, string.match(improvements_text, "validation steps"))
end

-- Test reasoning quality analysis
T["reflects on steps with poor reasoning coverage"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    cot:add_step("analysis", "Step 1", "", "step1")  -- no reasoning
    cot:add_step("reasoning", "Step 2", "", "step2")  -- no reasoning
    cot:add_step("task", "Step 3", "Good reasoning", "step3")  -- has reasoning
    reflection = cot:reflect()
  ]])

  local reflection = child.lua_get("reflection")

  h.expect_contains("more detailed reasoning", table.concat(reflection.improvements, " "))
end

T["reflects on steps with good reasoning coverage"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    cot:add_step("analysis", "Step 1", "Good reasoning 1", "step1")
    cot:add_step("reasoning", "Step 2", "Good reasoning 2", "step2")
    cot:add_step("task", "Step 3", "Good reasoning 3", "step3")
    reflection = cot:reflect()
  ]])

  local reflection = child.lua_get("reflection")

  h.expect_contains("Good coverage of reasoning", table.concat(reflection.insights, " "))
end

-- Test step distribution analysis
T["reflects on step distribution"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    cot:add_step("analysis", "Step 1", "Reasoning", "step1")
    cot:add_step("analysis", "Step 2", "Reasoning", "step2")
    cot:add_step("task", "Step 3", "Reasoning", "step3")
    reflection = cot:reflect()
  ]])

  local reflection = child.lua_get("reflection")

  local insights = table.concat(reflection.insights, " ")
  h.expect_contains("analysis:2", insights)
  h.expect_contains("task:1", insights)
end

-- Test helper function
T["table_to_strings helper works correctly"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    test_table = { foo = 1, bar = 2, baz = "test" }
    strings = cot:table_to_strings(test_table)
  ]])

  local strings = child.lua_get("strings")

  h.eq(3, #strings)
  -- Sort to ensure consistent ordering for testing
  table.sort(strings)
  h.eq("bar:2", strings[1])
  h.eq("baz:test", strings[2])
  h.eq("foo:1", strings[3])
end

T["table_to_strings works with empty table"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    strings = cot:table_to_strings({})
  ]])

  local strings = child.lua_get("strings")
  h.eq(0, #strings)
end

-- Test edge cases
T["handles steps with whitespace-only content"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    success, message = cot:add_step("analysis", "   ", "Reasoning", "step1")
  ]])

  local success = child.lua_get("success")
  local steps = child.lua_get("cot.steps")

  h.eq(true, success) -- whitespace content is allowed
  h.eq("   ", steps[1].content)
end

T["preserves step order across operations"] = function()
  child.lua([[
    cot = ChainOfThoughts.new("Test problem")
    cot:add_step("analysis", "First", "R1", "step1")
    cot:add_step("reasoning", "Second", "R2", "step2")
    cot:add_step("validation", "Third", "R3", "step3")
    cot:add_step("task", "Fourth", "R4", "step4")
  ]])

  local steps = child.lua_get("cot.steps")

  h.eq("First", steps[1].content)
  h.eq("Second", steps[2].content)
  h.eq("Third", steps[3].content)
  h.eq("Fourth", steps[4].content)
  h.eq(1, steps[1].step_number)
  h.eq(2, steps[2].step_number)
  h.eq(3, steps[3].step_number)
  h.eq(4, steps[4].step_number)
end

T["timestamps are reasonable"] = function()
  child.lua([[
    before_time = os.time()
    cot = ChainOfThoughts.new("Test problem")
    cot:add_step("analysis", "Test", "Reasoning", "step1")
    after_time = os.time()
    timestamp = cot.steps[1].timestamp
  ]])

  local before_time = child.lua_get("before_time")
  local after_time = child.lua_get("after_time")
  local timestamp = child.lua_get("timestamp")

  h.expect_truthy(timestamp >= before_time)
  h.expect_truthy(timestamp <= after_time)
end

return T
