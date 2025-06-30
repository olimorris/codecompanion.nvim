---@class CodeCompanion.Chat.ContextSummarizer
---@field chat CodeCompanion.Chat The chat instance
---@field adapter CodeCompanion.Adapter The adapter to use for summarization
---@field config table The configuration for the summarizer
local ContextSummarizer = {}

local log = require("codecompanion.utils.log")
local tokens = require("codecompanion.utils.tokens")
local client = require("codecompanion.http")
local config = require("codecompanion.config")
local util = require("codecompanion.utils")

---@param args { chat: CodeCompanion.Chat, adapter: CodeCompanion.Adapter, config?: table }
function ContextSummarizer.new(args)
  local self = setmetatable({
    chat = args.chat,
    adapter = args.adapter,
    config = args.config or {},
  }, { __index = ContextSummarizer })

  return self
end

---Generate a summary of conversation history (async version)
---@param messages_to_summarize table The messages to summarize
---@param summary_context table Context information for the summary
---@param callback function Callback function to handle result: callback(summary, error_msg)
---@return nil
function ContextSummarizer:summarize_async(messages_to_summarize, summary_context, callback)
  if not messages_to_summarize or #messages_to_summarize == 0 then
    return callback(nil, "No messages to summarize")
  end

  log:info("[ContextSummarizer] Starting async summarization of %d messages", #messages_to_summarize)

  -- Show initial notification
  vim.schedule(function()
    util.notify("Starting context summarization...", vim.log.levels.INFO)
  end)

  -- Check if adapter has required handler
  if not self.adapter.handlers or not self.adapter.handlers.chat_output then
    vim.schedule(function()
      util.notify("Context summarization failed: Adapter not compatible", vim.log.levels.WARN)
    end)
    return callback(nil, "Adapter does not support chat output handling")
  end

  -- Log progress but don't show notification
  log:debug("[ContextSummarizer] Analyzing conversation history")

  -- Build the summarization prompt
  local system_prompt = self:build_summarization_prompt(summary_context)
  local user_content = self:format_messages_for_summary(messages_to_summarize)

  local summary_messages = {
    {
      role = config.constants.SYSTEM_ROLE,
      content = system_prompt,
    },
    {
      role = config.constants.USER_ROLE,
      content = user_content,
    },
  }

  log:debug("[ContextSummarizer] Summarization prompt length: %d tokens", 
           tokens.get_tokens(summary_messages))

  -- Log progress but don't show notification
  log:debug("[ContextSummarizer] Generating context summary")

  -- Use the adapter to generate summary
  local summary = ""
  local error_msg = nil

  local payload = {
    messages = self.adapter:map_roles(summary_messages),
    tools = {},
  }

  -- Create a request using optimized adapter settings for summarization
  local temp_adapter = vim.deepcopy(self.adapter)
  
  -- Apply summarization-specific settings for better performance
  if temp_adapter.schema then
    if temp_adapter.schema.temperature then
      temp_adapter.schema.temperature.default = 0.1 -- Lower temperature for more consistent summaries
    end
    if temp_adapter.schema.max_tokens then
      temp_adapter.schema.max_tokens.default = self.config.max_summary_tokens or 1000
    end
    -- Disable streaming for summarization to get complete response faster
    if temp_adapter.schema.stream then
      temp_adapter.schema.stream.default = false
    end
  end

  -- Set up timeout timer
  local timeout_timer = vim.loop.new_timer()
  local completed = false

  local function complete_summarization(final_summary, final_error)
    if completed then return end
    completed = true
    
    if timeout_timer then
      timeout_timer:stop()
      timeout_timer:close()
    end
    
    -- Only show notification on error or completion
    if final_error then
      vim.schedule(function()
        util.notify("Context summarization failed: " .. final_error, vim.log.levels.WARN)
      end)
    else
      log:info("[ContextSummarizer] Context summarization completed successfully")
    end
    
    callback(final_summary, final_error)
  end

  -- Start timeout timer (30 seconds)
  timeout_timer:start(30000, 0, function()
    complete_summarization(nil, "Summarization timed out after 30 seconds")
  end)

  -- The HTTP request will trigger RequestStarted/RequestFinished events
  -- which users can monitor with Fidget for progress display
  local summarization_request = client.new({ 
    adapter = temp_adapter,
    user_args = { event = "ContextSummarization" } -- Custom event suffix for summarization
  }):request(payload, {
    callback = function(err, data, adapter)
      if err and err.stderr ~= "{}" then
        error_msg = "Summarization failed: " .. err.stderr
        log:error("[ContextSummarizer] %s", error_msg)
        return complete_summarization(nil, error_msg)
      end

      if data then
        -- Log progress but don't show notification
        log:trace("[ContextSummarizer] Processing summarization response")
        
        local result = self.adapter.handlers.chat_output(self.adapter, data, {})
        if result and result.status == "success" and result.output and result.output.content then
          summary = summary .. (result.output.content or "")
        elseif result and result.status == "error" then
          error_msg = "Summarization error: " .. (result.output or "Unknown error")
          log:error("[ContextSummarizer] %s", error_msg)
          return complete_summarization(nil, error_msg)
        end
      end
    end,
    done = function()
      -- Log progress but don't show notification
      log:debug("[ContextSummarizer] Finalizing context summary")
      
      if summary and summary ~= "" then
        log:info("[ContextSummarizer] Generated summary: %d characters", #summary)
        complete_summarization(vim.trim(summary), nil)
      else
        complete_summarization(nil, "Empty summary generated")
      end
    end,
  }, {
    bufnr = self.chat.bufnr,
    strategy = "chat",
    context = { summarization = true }, -- Add context to indicate this is a summarization request
  })
end

---Generate a summary of conversation history (sync version for backward compatibility)
---@param messages_to_summarize table The messages to summarize
---@param summary_context table Context information for the summary
---@return string|nil summary The generated summary
---@return string|nil error_message Any error that occurred
function ContextSummarizer:summarize(messages_to_summarize, summary_context)
  if not messages_to_summarize or #messages_to_summarize == 0 then
    return nil, "No messages to summarize"
  end

  log:info("[ContextSummarizer] Starting summarization of %d messages", #messages_to_summarize)

  -- Build the summarization prompt
  local system_prompt = self:build_summarization_prompt(summary_context)
  local user_content = self:format_messages_for_summary(messages_to_summarize)

  local summary_messages = {
    {
      role = config.constants.SYSTEM_ROLE,
      content = system_prompt,
    },
    {
      role = config.constants.USER_ROLE,
      content = user_content,
    },
  }

  log:debug("[ContextSummarizer] Summarization prompt length: %d tokens", 
           tokens.get_tokens(summary_messages))

  -- Check if adapter has required handler
  if not self.adapter.handlers or not self.adapter.handlers.chat_output then
    return nil, "Adapter does not support chat output handling"
  end

  -- Use the adapter to generate summary
  local summary = ""
  local success = false
  local error_msg = nil

  local payload = {
    messages = self.adapter:map_roles(summary_messages),
    tools = {},
  }

  -- Create a request using optimized adapter settings for summarization
  local temp_adapter = vim.deepcopy(self.adapter)
  
  -- Apply summarization-specific settings for better performance
  if temp_adapter.schema then
    if temp_adapter.schema.temperature then
      temp_adapter.schema.temperature.default = 0.1 -- Lower temperature for more consistent summaries
    end
    if temp_adapter.schema.max_tokens then
      temp_adapter.schema.max_tokens.default = self.config.max_summary_tokens or 1000
    end
    -- Disable streaming for summarization to get complete response faster
    if temp_adapter.schema.stream then
      temp_adapter.schema.stream.default = false
    end
  end

  local summarization_request = client.new({ adapter = temp_adapter }):request(payload, {
    callback = function(err, data, adapter)
      if err and err.stderr ~= "{}" then
        error_msg = "Summarization failed: " .. err.stderr
        log:error("[ContextSummarizer] %s", error_msg)
        return
      end

      if data then
        -- Fix: Use self.adapter instead of adapter parameter
        local result = self.adapter.handlers.chat_output(self.adapter, data, {})
        if result and result.status == "success" and result.output and result.output.content then
          summary = summary .. (result.output.content or "")
        elseif result and result.status == "error" then
          error_msg = "Summarization error: " .. (result.output or "Unknown error")
          log:error("[ContextSummarizer] %s", error_msg)
        end
      end
    end,
    done = function()
      success = true
    end,
  })

  -- Use a more efficient async approach with smaller intervals
  local timeout = 30000 -- 30 seconds timeout in milliseconds
  
  -- Use vim.wait with a smaller interval for better responsiveness
  local ok = vim.wait(timeout, function()
    return success or error_msg ~= nil
  end, 10) -- Check every 10ms for better UI responsiveness

  if not ok then
    error_msg = "Summarization timed out after 30 seconds"
    log:error("[ContextSummarizer] %s", error_msg)
  end

  if error_msg then
    return nil, error_msg
  end

  if summary and summary ~= "" then
    log:info("[ContextSummarizer] Generated summary: %d characters", #summary)
    return vim.trim(summary), nil
  else
    return nil, "Empty summary generated"
  end
end

---Build the system prompt for summarization
---@param context table Context information for the summary
---@return string The system prompt
function ContextSummarizer:build_summarization_prompt(context)
  local prompt = [[You are an expert conversation summarizer. Your task is to create a concise but comprehensive summary of the conversation history provided.

CRITICAL: This is a context summarization due to length limits. You MUST include a clear metadata section at the beginning.

Requirements:
1. START with a "CONTEXT METADATA" section that includes:
   - Total number of files/references provided
   - List of file names or types
   - Tools that were used or mentioned
   - Important operations performed
   - Key configuration or setup details
2. Preserve all key decisions, conclusions, and important context
3. Maintain the logical flow of the conversation
4. Include any important code snippets, file paths, or technical details that are crucial for understanding
5. Note any ongoing tasks or unresolved issues
6. Preserve tool usage results and their outcomes
7. Keep the summary focused and relevant to the current conversation context
8. Use clear, structured formatting with appropriate headings
9. Maintain the chronological order of important events

Format:
```
CONTEXT METADATA:
- Files provided: [count] files ([list key files])
- Tools used: [list tools]
- Key operations: [list important actions]
- Status: [current state]

CONVERSATION SUMMARY:
[detailed summary content]
```

Focus on information that would be essential for continuing the conversation effectively.]]

  if context and context.current_task then
    prompt = prompt .. "\n\nCurrent task context: " .. context.current_task
  end

  if context and context.preserve_tools then
    prompt = prompt .. "\n\nPay special attention to tool usage and their results, as these are critical for the ongoing task."
  end

  -- Add metadata hints if available
  if context and context.metadata then
    prompt = prompt .. "\n\nKnown context metadata to preserve:"
    if context.metadata.file_count then
      prompt = prompt .. "\n- File count: " .. context.metadata.file_count
    end
    if context.metadata.reference_types then
      prompt = prompt .. "\n- Reference types: " .. table.concat(context.metadata.reference_types, ", ")
    end
    if context.metadata.tools_used then
      prompt = prompt .. "\n- Tools used: " .. table.concat(context.metadata.tools_used, ", ")
    end
  end

  return prompt
end

---Format messages for summarization
---@param messages table The messages to format
---@return string The formatted content
function ContextSummarizer:format_messages_for_summary(messages)
  local formatted_parts = {}
  
  table.insert(formatted_parts, "=== CONVERSATION HISTORY TO SUMMARIZE ===\n")
  
  for i, msg in ipairs(messages) do
    local role_name = "UNKNOWN"
    if msg.role == config.constants.USER_ROLE then
      role_name = "USER"
    elseif msg.role == config.constants.LLM_ROLE then
      role_name = "ASSISTANT"
    elseif msg.role == config.constants.SYSTEM_ROLE then
      role_name = "SYSTEM"
    end

    table.insert(formatted_parts, string.format("--- %s MESSAGE %d ---", role_name, i))
    
    if msg.content then
      table.insert(formatted_parts, msg.content)
    end
    
    if msg.tool_calls and #msg.tool_calls > 0 then
      table.insert(formatted_parts, "\n[TOOL CALLS USED:]")
      for _, tool_call in ipairs(msg.tool_calls) do
        table.insert(formatted_parts, string.format("- %s: %s", tool_call.name or "unknown", tool_call.arguments or "{}"))
      end
    end
    
    table.insert(formatted_parts, "")
  end
  
  table.insert(formatted_parts, "=== END CONVERSATION HISTORY ===")
  
  return table.concat(formatted_parts, "\n")
end

---Collect metadata about the conversation context
---@param messages table The messages to analyze
---@param chat_refs table The chat references (files, tools, etc.)
---@return table Metadata about the context
function ContextSummarizer:collect_context_metadata(messages, chat_refs)
  local metadata = {
    file_count = 0,
    reference_types = {},
    tools_used = {},
    file_names = {},
    tool_calls_count = 0,
    user_messages_count = 0,
    llm_messages_count = 0,
  }
  
  -- Analyze references
  if chat_refs then
    for _, ref in ipairs(chat_refs) do
      if ref.id:match("<file>.*</file>") then
        metadata.file_count = metadata.file_count + 1
        local file_path = ref.id:match("<file>(.*)</file>")
        if file_path then
          table.insert(metadata.file_names, file_path)
        end
        if not vim.tbl_contains(metadata.reference_types, "files") then
          table.insert(metadata.reference_types, "files")
        end
      elseif ref.id:match("<tool>.*</tool>") then
        local tool_name = ref.id:match("<tool>(.*)</tool>")
        if tool_name and not vim.tbl_contains(metadata.tools_used, tool_name) then
          table.insert(metadata.tools_used, tool_name)
        end
        if not vim.tbl_contains(metadata.reference_types, "tools") then
          table.insert(metadata.reference_types, "tools")
        end
      elseif ref.id:match("<buf>.*</buf>") then
        if not vim.tbl_contains(metadata.reference_types, "buffers") then
          table.insert(metadata.reference_types, "buffers")
        end
      end
    end
  end
  
  -- Analyze messages
  for _, msg in ipairs(messages) do
    if msg.role == config.constants.USER_ROLE then
      metadata.user_messages_count = metadata.user_messages_count + 1
    elseif msg.role == config.constants.LLM_ROLE then
      metadata.llm_messages_count = metadata.llm_messages_count + 1
    end
    
    -- Count tool calls
    if msg.tool_calls and #msg.tool_calls > 0 then
      metadata.tool_calls_count = metadata.tool_calls_count + #msg.tool_calls
      for _, tool_call in ipairs(msg.tool_calls) do
        if tool_call.name and not vim.tbl_contains(metadata.tools_used, tool_call.name) then
          table.insert(metadata.tools_used, tool_call.name)
        end
      end
    end
  end
  
  return metadata
end

---Calculate the tokens used by messages
---@param messages table The messages to calculate tokens for
---@return number The estimated token count
function ContextSummarizer:calculate_tokens(messages)
  return tokens.get_tokens(messages)
end

---Check if summarization is needed based on token count
---@param messages table All messages in the conversation
---@param context_limit number The context window limit
---@param threshold_ratio number The ratio of context limit to trigger summarization (default: 0.85)
---@return boolean Whether summarization is needed
function ContextSummarizer:should_summarize(messages, context_limit, threshold_ratio)
  threshold_ratio = threshold_ratio or 0.85
  local current_tokens = self:calculate_tokens(messages)
  local threshold = context_limit * threshold_ratio
  
  log:debug("[ContextSummarizer] Token check: %d/%d (threshold: %d)", 
           current_tokens, context_limit, threshold)
  
  return current_tokens > threshold
end

---Split messages into summary and keep portions
---@param messages table All messages
---@param keep_recent_count number Number of recent messages to keep unsummarized
---@return table messages_to_summarize, table messages_to_keep
function ContextSummarizer:split_messages_for_summary(messages, keep_recent_count)
  keep_recent_count = keep_recent_count or 3
  
  if #messages <= keep_recent_count then
    return {}, messages
  end
  
  local split_index = #messages - keep_recent_count
  local messages_to_summarize = {}
  local messages_to_keep = {}
  
  for i = 1, split_index do
    table.insert(messages_to_summarize, messages[i])
  end
  
  for i = split_index + 1, #messages do
    table.insert(messages_to_keep, messages[i])
  end
  
  return messages_to_summarize, messages_to_keep
end

return ContextSummarizer 