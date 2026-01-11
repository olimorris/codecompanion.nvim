local formatter = require("codecompanion.interactions.chat.acp.formatters")
local log = require("codecompanion.utils.log")
local plan_icons = require("codecompanion.interactions.chat.ui.plan_icons")

-- Keep a record of UI changes in the chat buffer

---@class CodeCompanion.Chat.ACPHandler
---@field chat CodeCompanion.Chat
---@field output table Standard output message from the Agent
---@field reasoning table Reasoning output from the Agent
---@field tools table<string, table> Cache of tool calls by their ID
local ACPHandler = {}

local ACPHandlerUI = {} -- Cache of tool call UI states by chat buffer

---@param chat CodeCompanion.Chat
---@return CodeCompanion.Chat.ACPHandler
function ACPHandler.new(chat)
  local self = setmetatable({
    chat = chat,
    output = {},
    reasoning = {},
    tools = {},
  }, { __index = ACPHandler })

  -- Lazy-initialize plan state in chat object (persists across handler instances)
  if not chat.acp_plan then
    chat.acp_plan = {
      entries = {},
      line_start = nil,
      line_end = nil,
      icon_extmark_id = nil,
    }
  end

  ACPHandlerUI[chat.bufnr] = {}

  return self --[[@type CodeCompanion.Chat.ACPHandler]]
end

---Return the ACP client
---@return CodeCompanion.ACP.Connection
local get_client = function()
  return require("codecompanion.acp")
end

---Merge an incoming tool call/update into the cache
---@param existing table|nil
---@param incoming table|nil
---@return table
local function merge_tool_call(existing, incoming)
  local out = vim.deepcopy(existing or {})
  for k, v in pairs(incoming or {}) do
    if v ~= vim.NIL then
      out[k] = v
    end
  end
  return out
end

---Submit payload to ACP and handle streaming response
---@param payload table The payload to send to the LLM
---@return table|nil Request object or nil on error
function ACPHandler:submit(payload)
  if not self:ensure_connection() then
    self.chat.status = "error"
    return self.chat:done(self.output)
  end

  return self:create_and_send_prompt(payload)
end

---Ensure ACP connection is established
---@return boolean success
function ACPHandler:ensure_connection()
  if not self.chat.acp_connection then
    self.chat.acp_connection = get_client().new({
      adapter = self.chat.adapter, --[[@type CodeCompanion.ACPAdapter]]
    })

    local connected = self.chat.acp_connection:connect_and_initialize()

    if not connected then
      return false
    end

    -- Map bufnr -> session_id so completion providers can look up ACP commands for this buffer
    if self.chat.acp_connection.session_id then
      local acp_commands = require("codecompanion.interactions.chat.acp.commands")
      acp_commands.link_buffer_to_session(self.chat.bufnr, self.chat.acp_connection.session_id)
    end

    self.chat:update_metadata()
  end
  return true
end

---Transform ACP commands in messages from \command to /command
---@param messages table The messages to transform
---@return table The transformed messages
function ACPHandler:transform_acp_commands(messages)
  if not self.chat.acp_connection or not self.chat.acp_connection.session_id then
    return messages
  end

  -- Get available ACP commands for this session
  local acp_commands = require("codecompanion.interactions.chat.acp.commands")
  local commands = acp_commands.get_commands_for_session(self.chat.acp_connection.session_id)

  if #commands == 0 then
    return messages
  end

  -- Get trigger character
  local config = require("codecompanion.config")
  local trigger = "\\"
  if config.interactions.chat.slash_commands.opts and config.interactions.chat.slash_commands.opts.acp then
    trigger = config.interactions.chat.slash_commands.opts.acp.trigger or "\\"
  end
  local escaped_trigger = vim.pesc(trigger)

  -- Transform messages by replacing each known command
  local transformed = vim.deepcopy(messages)
  for _, message in ipairs(transformed) do
    if message.content and type(message.content) == "string" then
      -- Replace \command with /command for each known ACP command
      for _, cmd in ipairs(commands) do
        local escaped_name = vim.pesc(cmd.name)

        -- Pattern with trailing space
        local pattern_space = escaped_trigger .. escaped_name .. "(%s)"
        message.content = message.content:gsub(pattern_space, "/" .. cmd.name .. "%1")

        -- Pattern at end of string or followed by non-word character
        local pattern_end = escaped_trigger .. escaped_name .. "([^%w])"
        message.content = message.content:gsub(pattern_end, "/" .. cmd.name .. "%1")

        -- Pattern at end of string
        local pattern_eol = escaped_trigger .. escaped_name .. "$"
        message.content = message.content:gsub(pattern_eol, "/" .. cmd.name)
      end
    end
  end

  return transformed
end

---Create and configure the prompt request with all handlers
---@param payload table
---@return table Request object
function ACPHandler:create_and_send_prompt(payload)
  -- Transform ACP commands before sending
  local transformed_payload = vim.deepcopy(payload)
  transformed_payload.messages = self:transform_acp_commands(payload.messages)

  return self.chat.acp_connection
    :session_prompt(transformed_payload.messages)
    :on_message_chunk(function(content)
      self:handle_message_chunk(content)
    end)
    :on_thought_chunk(function(content)
      self:handle_thought_chunk(content)
    end)
    :on_plan(function(entries)
      self:handle_plan(entries)
    end)
    :on_tool_call(function(tool_call)
      self:handle_tool_call(tool_call)
    end)
    :on_tool_update(function(tool_update)
      self:handle_tool_update(tool_update)
    end)
    :on_permission_request(function(request)
      self:handle_permission_request(request)
    end)
    :on_complete(function(stop_reason)
      self:handle_completion(stop_reason)
    end)
    :on_error(function(error)
      self:handle_error(error)
    end)
    :with_options({ bufnr = self.chat.bufnr, interaction = "chat" })
    :send()
end

---Handle incoming message chunks
---@param content string
function ACPHandler:handle_message_chunk(content)
  table.insert(self.output, content)
  self.chat:add_buf_message(
    { role = require("codecompanion.config").constants.LLM_ROLE, content = content },
    { type = self.chat.MESSAGE_TYPES.LLM_MESSAGE }
  )
end

---Handle incoming thought chunks
---@param content string
function ACPHandler:handle_thought_chunk(content)
  table.insert(self.reasoning, content)
  self.chat:add_buf_message(
    { role = require("codecompanion.config").constants.LLM_ROLE, content = content },
    { type = self.chat.MESSAGE_TYPES.REASONING_MESSAGE }
  )
end

---Output tool call to the chat
---@param tool_call table
---@return nil
function ACPHandler:process_tool_call(tool_call)
  -- Cache the tool call to handle processing later on, such as a later permission request
  local id = tool_call.toolCallId

  local prev = self.tools[id]
  local merged = merge_tool_call(prev, tool_call)
  tool_call = merged or tool_call

  local ok, content = pcall(formatter.tool_message, tool_call, self.chat.adapter)
  if not ok then
    content = "[Error formatting tool output]"
  end

  -- Cache or cleanup
  if tool_call.status == "completed" then
    self.tools[id] = nil
  else
    self.tools[id] = merged
  end

  -- If the tool call has already written output to the chat buffer, then we can
  -- update it rather than adding a new line. We do this by keeping track in
  -- a global cache, segmented by chat buffer and tool call IDs
  if ACPHandlerUI[self.chat.bufnr][id] then
    local match = ACPHandlerUI[self.chat.bufnr][id]
    -- Whilst I've tried to account for all types of ACP tool output, I'm taking
    -- a cautious approach and wrapping line updates. Any failures and we'll
    -- just write the tool output onto a new line in the chat buffer
    ok, _ = pcall(function()
      self.chat:update_buf_line(
        match.line_number,
        content,
        { status = tool_call.status, icon_id = match.icon_id, priority = 120, virt_text_pos = "inline" }
      )
    end)

    -- Cleanup the cache
    if tool_call.status == "completed" then
      ACPHandlerUI[self.chat.bufnr][id] = nil
    end

    if ok then
      return
    end
    log:debug("[ACP::Handler] Failed to update tool call line for toolCallId %s", tool_call.toolCallId)
  end

  table.insert(self.output, content)
  local line_number = self.chat:add_buf_message({
    role = require("codecompanion.config").constants.LLM_ROLE,
    content = content,
  }, {
    status = tool_call.status or "in_progress",
    virt_text_pos = "inline",
    tools = { call_id = id },
    kind = tool_call.kind,
    type = self.chat.MESSAGE_TYPES.TOOL_MESSAGE,
  })

  ACPHandlerUI[self.chat.bufnr][id] = { line_number = line_number }
end

---Handle tool call notifications
---@param tool_call table
function ACPHandler:handle_tool_call(tool_call)
  return self:process_tool_call(tool_call)
end

---Handle tool call updates and their respective status
---@param tool_call table
function ACPHandler:handle_tool_update(tool_call)
  return self:process_tool_call(tool_call)
end

---Handle permission requests from the agent
---@param request table
---@return nil
function ACPHandler:handle_permission_request(request)
  local tool_call = request.tool_call

  if
    type(tool_call) == "table"
    and tool_call.toolCallId
    and (tool_call.content == nil or tool_call.content == vim.NIL)
  then
    local cached = self.tools[tool_call.toolCallId]
    if cached then
      -- Merge the cached tool call details into the request's tool call to enable the diff UI to activate
      request.tool_call = merge_tool_call(cached, tool_call)
    end
  end

  return require("codecompanion.interactions.chat.acp.request_permission").show(self.chat, request)
end

---Format plan entries as markdown
---@param entries table[]
---@return string[]
function ACPHandler:format_plan_markdown(entries)
  -- Note: Icon will be prepended by Plan formatter, so don't add it here
  local lines = { "## Plan", "" }

  for _, entry in ipairs(entries) do
    local checkbox = "[ ]"
    if entry.status == "in_progress" then
      checkbox = "[-]"
    elseif entry.status == "completed" then
      checkbox = "[x]"
    end

    local priority_indicator = ""
    if entry.priority == "high" then
      priority_indicator = " ⚡"
    elseif entry.priority == "low" then
      priority_indicator = " ⏸"
    end

    table.insert(lines, string.format("- %s %s%s", checkbox, entry.content, priority_indicator))
  end

  -- Add trailing newline for proper spacing
  table.insert(lines, "")

  return lines
end

---Handle agent plan updates
---@param entries table[] Array of plan entries
function ACPHandler:handle_plan(entries)
  if not entries or #entries == 0 then
    return
  end

  -- Format plan as markdown
  local lines = self:format_plan_markdown(entries)

  -- Note: line_start and line_end are stored as 0-based indices (Neovim API convention)
  log:debug(
    "[ACP::Handler] handle_plan called. Current line_start=%s, line_end=%s",
    tostring(self.chat.acp_plan.line_start),
    tostring(self.chat.acp_plan.line_end)
  )

  -- Check if we should update existing plan or create new one
  -- Rule: Update in-place if existing plan has any incomplete items
  local should_update_existing = false
  if self.chat.acp_plan.line_start and self.chat.acp_plan.entries then
    for _, entry in ipairs(self.chat.acp_plan.entries) do
      if entry.status ~= "completed" then
        should_update_existing = true
        break
      end
    end
  end

  if should_update_existing then
    -- Update existing plan in-place (has incomplete items)
    -- Search for the ## Plan header to handle line number shifts
    local buffer_lines = vim.api.nvim_buf_get_lines(self.chat.bufnr, 0, -1, false)
    local found_line = nil
    local plan_end_line = nil

    -- Search for the ## Plan header
    for i, line in ipairs(buffer_lines) do
      if line:match("^## Plan") then
        found_line = i - 1 -- Convert to 0-based
        -- Find the end of this plan block (next header or end of buffer)
        for j = i + 1, #buffer_lines do
          if buffer_lines[j]:match("^## ") then
            plan_end_line = j - 1 -- Convert to 0-based, exclusive of next header
            break
          end
        end
        -- If no next header found, plan extends to end
        if not plan_end_line then
          plan_end_line = #buffer_lines
        end
        break -- Use first ## Plan found
      end
    end

    if found_line then
      -- Look for blank line before ## Plan header (for icon)
      local actual_start = found_line
      if found_line > 0 and buffer_lines[found_line] == "" then
        actual_start = found_line - 1
      end

      -- Add blank line at beginning for icon
      table.insert(lines, 1, "")

      log:debug(
        "[ACP::Handler] Updating existing plan at line %d-%d with %d lines (has incomplete items)",
        actual_start,
        plan_end_line,
        #lines
      )

      self.chat.ui:unlock_buf()

      local ok, err = pcall(function()
        vim.api.nvim_buf_set_lines(self.chat.bufnr, actual_start, plan_end_line, false, lines)

        -- Update line tracking
        self.chat.acp_plan.line_start = actual_start
        self.chat.acp_plan.line_end = actual_start + #lines

        -- Trigger treesitter reparse
        if self.chat.chat_parser then
          vim.schedule(function()
            self.chat.chat_parser:invalidate(true)
            self.chat.chat_parser:parse()
          end)
        end

        -- Reapply icon
        if self.chat.acp_plan.icon_extmark_id then
          plan_icons:clear_icon(self.chat.bufnr, self.chat.acp_plan.icon_extmark_id)
        end
        self.chat.acp_plan.icon_extmark_id = plan_icons.apply(self.chat.bufnr, self.chat.acp_plan.line_start)

        -- Apply highlight to entire plan section
        -- vim.schedule(function()
        --   plan_icons.apply_highlight(
        --     self.chat.bufnr,
        --     self.chat.acp_plan.line_start,
        --     self.chat.acp_plan.line_end - 1 -- end_line is exclusive, so subtract 1
        --   )
        -- end)

        -- Apply sign column indicators to entire plan section
        vim.schedule(function()
          plan_icons.apply_signs(
            self.chat.bufnr,
            self.chat.acp_plan.line_start,
            self.chat.acp_plan.line_end - 1 -- end_line is exclusive, so subtract 1
          )
        end)

        -- Recreate fold if enabled
        if require("codecompanion.config").display.chat.fold_plan then
          vim.schedule(function()
            self.chat.ui.folds:create_plan_fold(
              self.chat,
              self.chat.acp_plan.line_start,
              self.chat.acp_plan.line_end - 1
            )
          end)
        end
      end)

      if not ok then
        log:debug("[ACP::Handler] Failed to update plan: %s. Will create new section.", tostring(err))
        self.chat.acp_plan.line_start = nil
      else
        log:debug("[ACP::Handler] Successfully updated plan at line %d", self.chat.acp_plan.line_start)
        -- Cache current entries for next comparison
        self.chat.acp_plan.entries = vim.deepcopy(entries)
        return -- Successfully updated, exit
      end
    else
      log:debug("[ACP::Handler] Could not find existing plan block, will create new")
      self.chat.acp_plan.line_start = nil
    end
  else
    if self.chat.acp_plan.line_start then
      log:debug("[ACP::Handler] Existing plan is complete, creating new plan block")
    end
    -- Clear state to create fresh plan
    self.chat.acp_plan.line_start = nil
  end

  if not self.chat.acp_plan.line_start then
    -- Add new plan section through add_buf_message to ensure proper markdown rendering
    -- The Plan formatter will add a blank line for the icon
    log:debug("[ACP::Handler] Creating new plan section with %d formatted lines", #lines)

    -- Convert lines array to string content for the message
    local content = table.concat(lines, "\n")

    -- Use add_buf_message with PLAN_MESSAGE type to route through Plan formatter
    -- Plan formatter will add blank line at start, so total lines = #lines + 1
    local line_number = self.chat:add_buf_message({
      role = require("codecompanion.config").constants.LLM_ROLE,
      content = content,
    }, {
      type = self.chat.MESSAGE_TYPES.PLAN_MESSAGE,
    })

    log:debug("[ACP::Handler] add_buf_message returned line_number=%s", tostring(line_number))

    if line_number then
      -- Plan formatter adds 1 blank line for icon at the start
      -- So total lines written = #lines + 1
      local total_lines = #lines + 1

      -- add_buf_message returns the line AFTER the content (end_line_written + 1)
      -- So the actual start line is line_number - total_lines
      local actual_start = line_number - total_lines

      -- Track line positions (0-based, line_end is exclusive)
      self.chat.acp_plan.line_start = actual_start
      self.chat.acp_plan.line_end = line_number

      log:debug(
        "[ACP::Handler] Tracked new plan: line_start=%d, line_end=%d (exclusive, %d lines)",
        self.chat.acp_plan.line_start,
        self.chat.acp_plan.line_end,
        total_lines
      )

      -- Icon is already applied by Builder via Plan formatter's _icon_info
      -- No need to apply it manually here

      -- Apply highlight to entire plan section
      -- vim.schedule(function()
      --   plan_icons.apply_highlight(
      --     self.chat.bufnr,
      --     self.chat.acp_plan.line_start,
      --     self.chat.acp_plan.line_end - 1 -- end_line is exclusive, so subtract 1
      --   )
      -- end)

      -- Apply sign column indicators to entire plan section
      vim.schedule(function()
        plan_icons.apply_signs(
          self.chat.bufnr,
          self.chat.acp_plan.line_start,
          self.chat.acp_plan.line_end - 1 -- end_line is exclusive, so subtract 1
        )
      end)

      -- Create fold if fold_plan is enabled
      if require("codecompanion.config").display.chat.fold_plan then
        vim.schedule(function()
          self.chat.ui.folds:create_plan_fold(self.chat, actual_start, self.chat.acp_plan.line_end - 1)
        end)
      end
    end
  end

  -- Cache current entries for potential future diffing
  self.chat.acp_plan.entries = vim.deepcopy(entries)
end

---Handle completion
---@param stop_reason string|nil
function ACPHandler:handle_completion(stop_reason)
  if not self.chat.status or self.chat.status == "" then
    self.chat.status = "success"
  end
  self.chat:done(self.output, self.reasoning, {})
end

---Handle errors
---@param error string
function ACPHandler:handle_error(error)
  self.chat.status = "error"
  log:error("[ACP::Handler] %s", error)

  self.chat:add_buf_message(
    { role = require("codecompanion.config").constants.LLM_ROLE, content = string.format("````txt\n%s\n````", error) },
    { type = self.chat.MESSAGE_TYPES.LLM_MESSAGE }
  )

  self.chat:done(self.output)
end

return ACPHandler
