---@class CodeCompanion.Chat.IterationManager
---@field chat CodeCompanion.Chat The chat instance
---@field config table The configuration for iteration management
---@field current_iterations number Current iteration count for the current task
---@field max_iterations number Maximum iterations allowed per task
---@field iteration_history table History of iterations with metadata
local IterationManager = {}

local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

---Validate configuration parameters
---@param config table Configuration to validate
---@return table validated_config, string|nil error_message
local function validate_config(config)
  local errors = {}

  if
    config.max_iterations_per_task
    and (type(config.max_iterations_per_task) ~= "number" or config.max_iterations_per_task < 1)
  then
    table.insert(errors, "max_iterations_per_task must be a positive number")
  end

  if
    config.iteration_increase_amount
    and (type(config.iteration_increase_amount) ~= "number" or config.iteration_increase_amount < 1)
  then
    table.insert(errors, "iteration_increase_amount must be a positive number")
  end

  if
    config.user_confirmation_timeout
    and (type(config.user_confirmation_timeout) ~= "number" or config.user_confirmation_timeout < 1000)
  then
    table.insert(errors, "user_confirmation_timeout must be at least 1000ms")
  end

  if config.show_iteration_progress and type(config.show_iteration_progress) ~= "boolean" then
    table.insert(errors, "show_iteration_progress must be a boolean")
  end

  if #errors > 0 then
    return config, "Invalid iteration config: " .. table.concat(errors, ", ")
  end

  return config, nil
end

---@param args { chat: CodeCompanion.Chat, config?: table }
function IterationManager.new(args)
  local default_config = {
    max_iterations_per_task = 20,
    iteration_increase_amount = 10,
    user_confirmation_timeout = 30000, -- 30 seconds
    show_iteration_progress = true,
  }

  local config = vim.tbl_deep_extend("force", default_config, args.config or {})

  -- Validate configuration
  local validated_config, error_msg = validate_config(config)
  if error_msg then
    log:error("[IterationManager] %s", error_msg)
    config = default_config -- Fall back to defaults
  else
    config = validated_config
  end

  local self = setmetatable({
    chat = args.chat,
    config = config,
    current_iterations = 0,
    max_iterations = config.max_iterations_per_task,
    iteration_history = {},
  }, { __index = IterationManager })

  return self
end

---Start a new task (reset iteration counter)
---@param task_description? string Optional description of the task
function IterationManager:start_task(task_description)
  self.current_iterations = 0
  self.iteration_history = {}

  log:info("[IterationManager] Starting new task: %s", task_description or "Unknown task")
  log:debug("[IterationManager] Max iterations set to: %d", self.max_iterations)

  if task_description then
    table.insert(self.iteration_history, {
      type = "task_start",
      description = task_description,
      timestamp = os.time(),
    })
  end
end

---Common iteration increment logic
---@param iteration_type string Type of iteration
---@return boolean Whether limit was reached
function IterationManager:_increment_iteration(iteration_type)
  self.current_iterations = self.current_iterations + 1

  -- Record iteration in history
  table.insert(self.iteration_history, {
    type = iteration_type,
    iteration_number = self.current_iterations,
    timestamp = os.time(),
  })

  log:debug("[IterationManager] Iteration %d/%d (%s)", self.current_iterations, self.max_iterations, iteration_type)

  -- Show progress if enabled
  if self.config.show_iteration_progress then
    self:show_iteration_progress()
  end

  return self.current_iterations >= self.max_iterations
end

---Record user decision in history
---@param approved boolean Whether user approved continuation
function IterationManager:_record_user_decision(approved)
  if approved then
    self.max_iterations = self.max_iterations + self.config.iteration_increase_amount
    log:info("[IterationManager] User approved continuation. New limit: %d", self.max_iterations)

    table.insert(self.iteration_history, {
      type = "user_approved_continuation",
      iteration_number = self.current_iterations,
      new_limit = self.max_iterations,
      timestamp = os.time(),
    })
  else
    log:info("[IterationManager] User declined continuation. Stopping iterations.")

    table.insert(self.iteration_history, {
      type = "user_cancelled",
      iteration_number = self.current_iterations,
      timestamp = os.time(),
    })
  end
end

---Increment iteration count and check if limit is reached (async version)
---@param iteration_type? string Type of iteration (e.g., "llm_request", "tool_execution")
---@param callback function Callback function: callback(continue_allowed, reason)
---@return nil
function IterationManager:increment_and_check_async(iteration_type, callback)
  iteration_type = iteration_type or "unknown"
  local limit_reached = self:_increment_iteration(iteration_type)

  if limit_reached then
    log:warn("[IterationManager] Iteration limit reached: %d/%d", self.current_iterations, self.max_iterations)

    self:request_user_confirmation_async(function(should_continue)
      self:_record_user_decision(should_continue)

      if should_continue then
        callback(true, nil)
      else
        callback(false, "User cancelled due to iteration limit")
      end
    end)
  else
    callback(true, nil)
  end
end

---Increment iteration count and check if limit is reached (sync version for backward compatibility)
---@param iteration_type? string Type of iteration (e.g., "llm_request", "tool_execution")
---@return boolean continue_allowed Whether to continue with the iteration
---@return string|nil reason Reason if continuation is not allowed
function IterationManager:increment_and_check(iteration_type)
  iteration_type = iteration_type or "unknown"
  local limit_reached = self:_increment_iteration(iteration_type)

  if limit_reached then
    log:warn("[IterationManager] Iteration limit reached: %d/%d", self.current_iterations, self.max_iterations)

    local should_continue = self:request_user_confirmation()
    self:_record_user_decision(should_continue)

    if should_continue then
      return true, nil
    else
      return false, "User cancelled due to iteration limit"
    end
  end

  return true, nil
end

---Request user confirmation to continue iterations (async version)
---@param callback function Callback function: callback(should_continue)
---@return nil
function IterationManager:request_user_confirmation_async(callback)
  local message = string.format(
    "CodeCompanion has performed %d iterations. This might indicate a complex task or potential issue.",
    self.current_iterations
  )

  local details = string.format(
    "Iteration history:\n%s\n\nDo you want to continue with more iterations?",
    self:format_iteration_summary()
  )

  log:info("[IterationManager] Requesting async user confirmation for continued iterations")

  -- Show notification about the iteration limit
  util.notify(
    string.format("Iteration limit reached (%d iterations). Please confirm to continue.", self.current_iterations),
    vim.log.levels.WARN
  )

  -- Use vim.ui.select for non-blocking confirmation
  local choices = { "Continue", "Cancel" }

  vim.ui.select(choices, {
    prompt = message,
    format_item = function(item)
      if item == "Continue" then
        return "Continue with more iterations"
      elseif item == "Cancel" then
        return "Stop iterations"
      end
      return item
    end,
  }, function(choice)
    if choice == "Continue" then
      callback(true)
    else
      callback(false)
    end
  end)

  -- Show detailed info in a separate notification
  vim.defer_fn(function()
    util.notify(details, vim.log.levels.INFO)
  end, 100)
end

---Request user confirmation to continue iterations (sync version for backward compatibility)
---@return boolean Whether user wants to continue
function IterationManager:request_user_confirmation()
  local message = string.format(
    "CodeCompanion has performed %d iterations. This might indicate a complex task or potential issue.\n\n"
      .. "Iteration history:\n%s\n\n"
      .. "Do you want to continue with more iterations?",
    self.current_iterations,
    self:format_iteration_summary()
  )

  log:info("[IterationManager] Requesting user confirmation for continued iterations")

  -- Show notification about the iteration limit
  util.notify(
    string.format("Iteration limit reached (%d iterations). Check for confirmation dialog.", self.current_iterations),
    vim.log.levels.WARN
  )

  -- Use non-blocking vim.ui.select with improved error handling
  local result = nil
  local selection_completed = false

  -- Set a timeout using a timer to avoid indefinite blocking
  local timeout_timer = vim.loop.new_timer()
  if timeout_timer then
    timeout_timer:start(self.config.user_confirmation_timeout or 30000, 0, function()
      if not selection_completed then
        selection_completed = true
        result = false -- Default to false on timeout
        log:warn("[IterationManager] User confirmation timed out, defaulting to cancel")
      end
      timeout_timer:close()
    end)
  end

  vim.ui.select({ "Continue", "Cancel" }, {
    prompt = message,
    format_item = function(item)
      return item
    end,
  }, function(choice)
    if not selection_completed then
      selection_completed = true
      result = choice == "Continue"
      if timeout_timer then
        timeout_timer:close()
      end
    end
  end)

  -- Wait for user response with improved error handling
  local wait_timeout = self.config.user_confirmation_timeout or 30000
  local ok = vim.wait(wait_timeout, function()
    return selection_completed
  end, 10) -- Check every 10ms for better UI responsiveness

  if not ok then
    log:warn("[IterationManager] User confirmation wait timed out")
    if timeout_timer then
      timeout_timer:close()
    end
    return false
  end

  return result or false
end

---Format a summary of iterations for user display
---@return string Formatted summary
function IterationManager:format_iteration_summary()
  if #self.iteration_history == 0 then
    return "No iteration history available"
  end

  local summary_lines = {}
  local type_counts = {}

  -- Count iteration types
  for _, item in ipairs(self.iteration_history) do
    if item.type ~= "task_start" and item.type ~= "user_approved_continuation" and item.type ~= "user_cancelled" then
      type_counts[item.type] = (type_counts[item.type] or 0) + 1
    end
  end

  -- Add type summary
  for type_name, count in pairs(type_counts) do
    table.insert(summary_lines, string.format("- %s: %d times", type_name, count))
  end

  if #summary_lines == 0 then
    table.insert(summary_lines, "- Various operations performed")
  end

  return table.concat(summary_lines, "\n")
end

---Show iteration progress notification with improved UX
function IterationManager:show_iteration_progress()
  local progress_message = string.format("Iteration %d/%d", self.current_iterations, self.max_iterations)
  local percentage = math.floor((self.current_iterations / self.max_iterations) * 100)

  -- Show progress notification with better timing and visual feedback
  local should_notify = false

  -- Show every 5 iterations, but also show at specific milestones
  if
    self.current_iterations % 5 == 0
    or percentage >= 75
    or (percentage >= 50 and self.current_iterations % 3 == 0)
  then
    should_notify = true
  end

  if should_notify then
    local icon = percentage >= 75 and "⚠️ " or "🔄 "
    local level = percentage >= 75 and vim.log.levels.WARN or vim.log.levels.INFO

    util.notify(string.format("%s%s (%d%%)", icon, progress_message, percentage), level)
  end

  -- Enhanced logging with more context
  if percentage >= 75 then
    log:warn("[IterationManager] Approaching limit: %s (%d%%)", progress_message, percentage)
  else
    log:debug("[IterationManager] %s (%d%%)", progress_message, percentage)
  end

  -- Fire event for external integrations
  require("codecompanion.utils").fire("IterationProgress", {
    current = self.current_iterations,
    max = self.max_iterations,
    percentage = percentage,
    chat_id = self.chat.id,
  })
end

---Show summarization progress with Fidget
---@param stage string Current stage of summarization
---@param message? string Optional custom message
function IterationManager:show_summarization_progress(stage, message)
  local has_fidget, fidget = pcall(require, "fidget")
  if not has_fidget or not fidget.progress then
    -- Fallback to regular notification
    util.notify(message or ("Context summarization: " .. stage), vim.log.levels.INFO)
    return
  end

  local progress_message = message or string.format("Context summarization: %s", stage)
  local percentage = 0

  -- Map stages to progress percentages
  local stage_progress = {
    ["starting"] = 10,
    ["analyzing"] = 25,
    ["generating"] = 50,
    ["processing"] = 75,
    ["completing"] = 90,
    ["done"] = 100,
  }

  percentage = stage_progress[stage] or 0

  -- Create or update Fidget progress for summarization
  local progress_handle = self._summarization_fidget_handle
  if not progress_handle then
    progress_handle = fidget.progress.handle.create({
      title = "CodeCompanion Context Summarization",
      message = progress_message,
      percentage = percentage,
      lsp_client = { name = "codecompanion" },
    })
    self._summarization_fidget_handle = progress_handle
  else
    -- Update existing handle
    progress_handle:report({
      message = progress_message,
      percentage = percentage,
    })
  end

  -- Complete the progress when done
  if stage == "done" or stage == "error" then
    vim.defer_fn(function()
      if self._summarization_fidget_handle then
        self._summarization_fidget_handle:finish()
        self._summarization_fidget_handle = nil
      end
    end, 1000) -- Keep visible for 1 second after completion
  end
end

---Clean up any progress state
function IterationManager:cleanup_progress()
  -- Clean up any internal state - no direct Fidget integration to clean up
  -- Progress display through events will be handled by user's Fidget configuration
  log:debug("[IterationManager] Cleaned up iteration progress state")
end

---Get current iteration status
---@return table Status information
function IterationManager:get_status()
  return {
    current_iterations = self.current_iterations,
    max_iterations = self.max_iterations,
    iterations_remaining = self.max_iterations - self.current_iterations,
    iteration_history = vim.deepcopy(self.iteration_history),
  }
end

---Check if iterations are approaching the limit
---@param warning_threshold? number Percentage of limit to trigger warning (default: 0.8)
---@return boolean Whether approaching limit
function IterationManager:is_approaching_limit(warning_threshold)
  warning_threshold = warning_threshold or 0.8
  local ratio = self.current_iterations / self.max_iterations
  return ratio >= warning_threshold
end

---Reset iteration counter (useful for debugging or manual reset)
function IterationManager:reset()
  local old_iterations = self.current_iterations
  self.current_iterations = 0
  self.iteration_history = {}

  -- Clean up any active progress displays
  self:cleanup_progress()

  log:info("[IterationManager] Reset iteration counter from %d to 0", old_iterations)
end

---Set a new maximum iteration limit
---@param new_limit number New maximum iteration count
function IterationManager:set_max_iterations(new_limit)
  local old_limit = self.max_iterations
  self.max_iterations = new_limit

  log:info("[IterationManager] Changed max iterations from %d to %d", old_limit, new_limit)

  -- Record the change
  table.insert(self.iteration_history, {
    type = "limit_changed",
    old_limit = old_limit,
    new_limit = new_limit,
    timestamp = os.time(),
  })
end

---Export iteration history for debugging or analysis
---@return table Detailed iteration history
function IterationManager:export_history()
  return {
    config = self.config,
    current_iterations = self.current_iterations,
    max_iterations = self.max_iterations,
    history = vim.deepcopy(self.iteration_history),
    export_timestamp = os.time(),
  }
end

return IterationManager
