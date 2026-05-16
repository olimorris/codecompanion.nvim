--[[
===============================================================================
    File:       codecompanion/interactions/chat/context_management/compaction.lua
    Author:     Oli Morris
-------------------------------------------------------------------------------
    Description:
      Replaces the conversation history with an LLM-generated summary. System
      messages and rules pass through verbatim; files, buffers, and images
      are swapped for reference placeholders, useful in future turns.
-------------------------------------------------------------------------------
    Attribution:
      If you use or distribute this code, please credit:
      Oli Morris (https://github.com/olimorris)
===============================================================================
--]]

local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local tags = require("codecompanion.interactions.shared.tags")
local tokens = require("codecompanion.utils.tokens")
local utils = require("codecompanion.utils")

local fmt = string.format

local CONSTANTS = {
  MIN_TOKEN_SAVINGS = 10000,

  -- This is based on the Claude Code compaction prompt (Ref: https://github.com/Piebald-AI/claude-code-system-prompts)
  PROMPT = [[Your task is to create a detailed summary of the conversation so far, paying close attention to the user's explicit requests and your previous actions.
This summary should be thorough in capturing technical details, code patterns, and architectural decisions that would be essential for continuing development work without losing context.

Before providing your final summary, you must first perform an analysis of the conversation, wrapped in <analysis></analysis> tags. Walk through the conversation chronologically, identifying explicit user requests, your responses, key decisions, and specific details like file paths, code snippets, and function signatures. This grounds your summary in the actual conversation rather than guessing.

Your summary should include the following sections:

1. Primary Request and Intent: Capture all of the user's explicit requests and intents in detail.
2. Key Technical Concepts: List all important technical concepts, technologies, and frameworks discussed.
3. Files and Code Sections: Enumerate specific files and code sections examined, modified, or created. Pay special attention to the most recent messages and include full code snippets where applicable and a summary of why each file read or edit is important.
4. Errors and fixes: List all errors that you ran into, and how you fixed them. Pay special attention to specific user feedback that you received, especially if the user told you to do something differently.
5. Problem Solving: Document problems solved and any ongoing troubleshooting efforts.
6. All user messages: List ALL user messages that are not tool results. These are critical for understanding the users' feedback and changing intent.
7. Pending Tasks: Outline any pending tasks that you have explicitly been asked to work on.
8. Current Work: Describe in detail precisely what was being worked on immediately before this summary request, paying special attention to the most recent messages from both user and assistant. Include file names and code snippets where applicable.
9. Optional Next Step: List the next step that you will take that is related to the most recent work you were doing. IMPORTANT: ensure that this step is DIRECTLY in line with the user's most recent explicit requests, and the task you were working on immediately before this summary request. If your last task was concluded, then only list next steps if they are explicitly in line with the user's request. Do not start on tangential requests without confirming with the user first. If there is a next step, include direct quotes from the most recent conversation showing exactly what task you were working on and where you left off. This should be verbatim to ensure there's no drift in task interpretation.

Here's an example of how your output should be structured:

<example>
<analysis>
[Your thought process, ensuring all points are covered thoroughly and accurately]
</analysis>

<summary>
1. Primary Request and Intent:
   [Detailed description]

2. Key Technical Concepts:
   - [Concept 1]
   - [Concept 2]

3. Files and Code Sections:
   - [File Name 1]
     - [Summary of why this file is important]
     - [Summary of the changes made to this file, if any]

````[language]
[Important Code Snippet]
````

4. Errors and fixes:
   - [Detailed description of error 1]:
     - [How you fixed the error]
     - [User feedback on the error if any]

5. Problem Solving:
   [Description of solved problems and ongoing troubleshooting]

6. All user messages:
   - [Detailed non tool use user message]

7. Pending Tasks:
   - [Task 1]

8. Current Work:
   [Precise description of current work]

9. Optional Next Step:
   [Optional Next step to take]
</summary>
</example>

Please provide your summary based on the conversation so far, following this structure and ensuring precision and thoroughness in your response.

Include the markdown only, without any additional commentary or explanation. If you're referencing any code in your summary, ensure that it is wrapped in FOUR backticks followed by the appropriate language identifier for syntax highlighting. For example:

````python
def example_function():
    pass
````

The conversation and corresponding messages to summarize, is as follows:

<conversation>%s</conversation>]],
  SUMMARY_PREFIX = "Below is a summary of a previous conversation:\n\n",
}

---@class CodeCompanion.Chat.ContextManagement.Compaction
local M = {}

M.PLACEHOLDERS = {
  buffer = "<important>Buffer content cleared during compaction. Request the buffer from the user if you need it.</important>",
  file = "<important>File content cleared during compaction. Re-read the file if you need it.</important>",
  image = "<important>Image content cleared during compaction. Request the image from the user if you need it.</important>",
}

---Calls the background interaction. Abstracted for easier mocking
local function background()
  return require("codecompanion.interactions.background")
end

---@alias CodeCompanion.Chat.ContextManagement.Compaction.Kind
---| "keep"
---| "drop"
---| "compacted_file"
---| "compacted_buffer"
---| "compacted_image"
---| "stale_summary" -- Previous summary message which should be removed on the next compaction cycle

---Classify a message for compaction
---@param message CodeCompanion.Chat.Message
---@return CodeCompanion.Chat.ContextManagement.Compaction.Kind
local function classify(message)
  local meta = message._meta or {}
  local context_management = meta.context_management or {}

  if message.role == config.constants.SYSTEM_ROLE then
    return "keep"
  end
  if context_management.compacted then
    return "keep"
  end

  local tag = meta.tag
  if tag == tags.RULES then
    return "keep"
  end
  if tag == tags.COMPACT_SUMMARY then
    return "stale_summary"
  end
  if tag == tags.FILE then
    return "compacted_file"
  end
  if tag == tags.BUFFER or tag == tags.EDITOR_CONTEXT then
    return "compacted_buffer"
  end
  if tag == tags.IMAGE then
    return "compacted_image"
  end

  return "drop"
end

---Build the message list that will remain in the chat after compaction, excluding the summary
---@param messages CodeCompanion.Chat.Messages
---@return CodeCompanion.Chat.Messages
local function messages_to_retain(messages)
  local retained = {}

  for _, message in ipairs(messages) do
    local kind = classify(message)

    if kind == "keep" then
      table.insert(retained, message)
    elseif kind == "stale_summary" or kind == "drop" then
      -- excluded
    else
      local placeholder
      if kind == "compacted_file" then
        placeholder = M.PLACEHOLDERS.file
      elseif kind == "compacted_buffer" then
        placeholder = M.PLACEHOLDERS.buffer
      elseif kind == "compacted_image" then
        placeholder = M.PLACEHOLDERS.image
      end

      local replaced = vim.deepcopy(message)
      replaced.content = placeholder
      replaced._meta = replaced._meta or {}
      replaced._meta.estimated_tokens = tokens.calculate(placeholder)
      replaced._meta.context_management = replaced._meta.context_management or {}
      replaced._meta.context_management.compacted = true

      if kind == "compacted_image" then
        -- The base64 payload and image-specific context are no longer needed.
        replaced.context = nil
      end

      table.insert(retained, replaced)
    end
  end

  return retained
end

---Curate the messages that will be used to generate the summary
---@param messages CodeCompanion.Chat.Messages
---@return string
local function messages_to_summarize(messages)
  local parts = {}

  for _, message in ipairs(messages) do
    local meta = message._meta or {}

    if message.role == config.constants.SYSTEM_ROLE then
      goto continue
    end
    -- Strip images as the summarizer may not support them and the base64 content is expensive
    if meta.tag == tags.IMAGE then
      goto continue
    end

    local content_parts = {}

    if message.tools and message.tools.calls then
      for _, call in ipairs(message.tools.calls) do
        local fn = call["function"]
        if fn and fn.name then
          table.insert(content_parts, fmt("Tool: %s(%s)", fn.name, fn.arguments or "{}"))
        end
      end
    end

    if type(message.content) == "string" and message.content ~= "" then
      table.insert(content_parts, message.content)
    end

    if #content_parts > 0 then
      table.insert(parts, fmt('<message role="%s">%s</message>', message.role, table.concat(content_parts, "\n")))
    end

    ::continue::
  end

  return table.concat(parts, "")
end

---Estimate the token savings from the compaction
---@param original CodeCompanion.Chat.Messages
---@param retained CodeCompanion.Chat.Messages
---@return number
local function estimate_savings(original, retained)
  local before = tokens.get_tokens(original)
  local after = tokens.get_tokens(retained)
  return math.max(0, before - after)
end

---@param chat CodeCompanion.Chat
---@param override? string|table
---@return CodeCompanion.HTTPAdapter|string|table
local function resolve_adapter(chat, override)
  if override == nil then
    return chat.adapter
  end
  return override
end

---@class CodeCompanion.Chat.ContextManagement.Compaction.RequestOpts
---@field adapter CodeCompanion.HTTPAdapter|string|table
---@field messages_text string The chat messages, formatted for the summariser
---@field on_done fun(content: string|nil)
---@field on_error fun(err: any)

---Ask an LLM to summarize the chat buffer's messages
---@param request CodeCompanion.Chat.ContextManagement.Compaction.RequestOpts
---@return nil
local function request_summary(request)
  local prompt = fmt(CONSTANTS.PROMPT, request.messages_text)

  background().new({ adapter = request.adapter }):ask({
    { role = config.constants.USER_ROLE, content = prompt },
  }, {
    method = "async",
    on_done = function(result)
      local content = result and result.output and result.output.content
      request.on_done(content)
    end,
    on_error = request.on_error,
  })
end

---@class CodeCompanion.Chat.ContextManagement.Compaction.Opts
---@field adapter? string|table Override adapter (nil | "name" | { name, model })
---@field fallback_to_chat_adapter? boolean Silently retry with the chat adapter on failure (default false)
---@field min_token_savings? number Skip if estimated savings under this (default 10000)

---Run compaction on a chat buffer
---@param chat CodeCompanion.Chat
---@param opts? CodeCompanion.Chat.ContextManagement.Compaction.Opts
---@return nil
function M.compact(chat, opts)
  opts = opts or {}

  if chat.adapter and chat.adapter.type == "acp" then
    return log:debug("[Compaction] Skipped — ACP adapters handle context themselves")
  end
  if chat._compacting then
    return log:debug("[Compaction] Skipped — a compaction is already in progress")
  end

  local original = chat.messages or {}
  local retained = messages_to_retain(original)
  local min_token_savings = opts.min_token_savings or CONSTANTS.MIN_TOKEN_SAVINGS
  local savings = estimate_savings(original, retained)

  if savings < min_token_savings then
    return log:warn("[Compaction] Skipped — estimated savings (%d) below threshold (%d)", savings, min_token_savings)
  end

  local messages_text = messages_to_summarize(original)
  if messages_text == "" then
    return log:warn("[Compaction] Skipped — nothing to summarise")
  end

  chat._compacting = true

  local primary = resolve_adapter(chat, opts.adapter)

  ---Apply the summary to the chat buffer and re-render the UI
  ---@param content string
  ---@return nil
  local function update_chat(content)
    local body = CONSTANTS.SUMMARY_PREFIX .. content
    table.insert(retained, {
      role = config.constants.USER_ROLE,
      content = body,
      opts = { visible = true },
      _meta = {
        cycle = chat.cycle,
        estimated_tokens = tokens.calculate(body),
        tag = tags.COMPACT_SUMMARY,
      },
    })
    chat.messages = retained
    chat._compacting = false
    if chat.ui and chat.ui.render then
      chat.ui:render(chat.buffer_context, chat.messages, chat.opts)
    end
    return utils.notify("Chat compacted")
  end

  ---Handle a failure in the compaction process
  ---@param reason string A message describing the failure reason
  ---@return nil
  local function fail(reason)
    chat._compacting = false
    return log:error("[Compaction] Failed: %s", reason)
  end

  ---Determine if we should attempt a fallback to the chat adapter on failure
  ---@return boolean
  local function should_fallback()
    return opts.fallback_to_chat_adapter == true and primary ~= chat.adapter
  end

  ---Run the fallback adapter if the primary fails or returns empty content
  ---@param reason string
  ---@return nil
  local function run_fallback(reason)
    log:debug("[Compaction] Falling back to chat adapter (%s)", reason)
    request_summary({
      adapter = chat.adapter,
      messages_text = messages_text,
      on_done = function(content)
        if content and content ~= "" then
          update_chat(content)
        else
          fail("fallback adapter returned empty content")
        end
      end,
      on_error = fail,
    })
  end

  request_summary({
    adapter = primary,
    messages_text = messages_text,
    on_done = function(content)
      if content and content ~= "" then
        update_chat(content)
      elseif should_fallback() then
        run_fallback("primary adapter returned empty content")
      else
        fail("compaction adapter returned empty content")
      end
    end,
    on_error = function(err)
      if should_fallback() then
        run_fallback(err)
      else
        fail(err)
      end
    end,
  })
end

return M
