local ChainOfThought = {}
ChainOfThought.__index = ChainOfThought

function ChainOfThought.new(problem)
  local self = setmetatable({}, ChainOfThought)
  self.problem = problem or ""
  self.steps = {}
  self.current_step = 0
  return self
end

local STEP_TYPES = {
  analysis = "Analysis and exploration of the problem",
  reasoning = "Logical deduction and inference",
  task = "Actionable implementation step",
  validation = "Verification and testing",
}

-- Add a step to the chain
function ChainOfThought:add_step(step_type, content, reasoning, step_id)
  -- Validate step type
  if STEP_TYPES[step_type] == nil then
    return false, "Invalid step type. Valid types are: " .. table.concat(vim.tbl_keys(STEP_TYPES), ", ")
  end

  -- Validate content
  if not content or content == "" then
    return false, "Step content cannot be empty"
  end

  -- Validate step_id
  if not step_id or step_id == "" then
    return false, "Step ID cannot be empty"
  end

  self.current_step = self.current_step + 1
  local step = {
    id = step_id,
    type = step_type,
    content = content,
    reasoning = reasoning or "",
    step_number = self.current_step,
    timestamp = os.time(),
  }

  table.insert(self.steps, step)
  return true, "Step added successfully"
end

-- Reflect on the reasoning process
function ChainOfThought:reflect()
  local insights = {}
  local improvements = {}

  -- Handle empty chain
  if #self.steps == 0 then
    return {
      total_steps = 0,
      insights = { "No steps to analyze" },
      improvements = { "Add reasoning steps to begin analysis" },
    }
  end

  -- Analyze step distribution
  local step_counts = {}
  for _, step in ipairs(self.steps) do
    step_counts[step.type] = (step_counts[step.type] or 0) + 1
  end

  table.insert(insights, string.format("Step distribution: %s", table.concat(self:table_to_strings(step_counts), ", ")))

  -- Check for logical progression
  local has_analysis = step_counts.analysis and step_counts.analysis > 0
  local has_reasoning = step_counts.reasoning and step_counts.reasoning > 0
  local has_tasks = step_counts.task and step_counts.task > 0
  local has_validation = step_counts.validation and step_counts.validation > 0

  if has_analysis and has_reasoning and has_tasks then
    table.insert(insights, "Good logical progression from analysis to implementation")
  else
    if not has_analysis then
      table.insert(improvements, "Consider adding analysis steps to explore the problem")
    end
    if not has_reasoning then
      table.insert(improvements, "Consider adding reasoning steps for logical deduction")
    end
    if not has_tasks then
      table.insert(improvements, "Consider adding task steps for actionable implementation")
    end
  end

  if not has_validation then
    table.insert(improvements, "Add validation steps to verify reasoning")
  end

  -- Check for reasoning quality
  local steps_with_reasoning = 0
  for _, step in ipairs(self.steps) do
    if step.reasoning and step.reasoning ~= "" then
      steps_with_reasoning = steps_with_reasoning + 1
    end
  end

  if steps_with_reasoning < #self.steps * 0.5 then
    table.insert(improvements, "Consider adding more detailed reasoning explanations to steps")
  else
    table.insert(insights, "Good coverage of reasoning explanations across steps")
  end

  return {
    total_steps = #self.steps,
    insights = insights,
    improvements = improvements,
  }
end

-- Helper function to convert table to strings
function ChainOfThought:table_to_strings(t)
  local result = {}
  for k, v in pairs(t) do
    table.insert(result, k .. ":" .. tostring(v))
  end
  return result
end

-- Export the module
return {
  ChainOfThought = ChainOfThought,
}
