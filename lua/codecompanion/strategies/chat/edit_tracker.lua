local DiffUtils = require("codecompanion.providers.diff.utils")
local Path = require("plenary.path")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")
local api = vim.api

---@class CodeCompanion.EditOperation
---@field id string Unique identifier for this edit operation
---@field timestamp number High-resolution timestamp when edit was made
---@field tool_name string Name of the tool that made the edit
---@field original_content string[] Content before the edit
---@field new_content string[] Content after the edit
---@field status "pending"|"accepted"|"rejected" Current status of the edit
---@field diff_id? string|number Associated diff ID for UI tracking
---@field metadata? table Additional metadata (patch info, line ranges, etc.)

---@class CodeCompanion.TrackedFile
---@field type "buffer"|"file" Type of tracked resource
---@field filepath? string File path (for files)
---@field bufnr? number Buffer number (for buffers)
---@field edit_operations CodeCompanion.EditOperation[] Array of all edit operations
---@field first_edit_timestamp number Timestamp of first edit
---@field last_edit_timestamp number Timestamp of last edit

---@class CodeCompanion.Chat.EditTracker
---@field tracked_files table<string, CodeCompanion.TrackedFile> Map of filepath/bufnr -> tracked file info
---@field enabled boolean Whether edit tracking is enabled
---@field edit_counter number Counter for generating unique edit IDs

---@class CodeCompanion.EditTracker
local EditTracker = {}

---Initialize edit tracking for a chat session
---@param chat CodeCompanion.Chat
---@return nil
function EditTracker.init(chat)
  if chat.edit_tracker then
    log:debug("[EditTracker] Already initialized for chat %d", chat.id)
    return
  end
  chat.edit_tracker = {
    tracked_files = {}, -- Map of filepath/bufnr -> tracked file info
    enabled = true,
    edit_counter = 0,
  }
  log:info("[EditTracker] Initialized edit tracking for chat %d", chat.id)
end

---Generate a unique key for tracking files/buffers
---@param edit_info table Must contain either filepath or bufnr
---@return string Unique key for the file/buffer
local function generate_key(edit_info)
  if edit_info.filepath then
    local p = Path:new(edit_info.filepath)
    local expanded_path = p:expand()
    log:trace("[EditTracker] Generated file key: file:%s", expanded_path)
    return "file:" .. expanded_path
  elseif edit_info.bufnr then
    log:trace("[EditTracker] Generated buffer key: buffer:%d", edit_info.bufnr)
    return "buffer:" .. edit_info.bufnr
  else
    local error_msg = "Edit info must have either filepath or bufnr"
    log:error("[EditTracker] %s. Received: %s", error_msg, vim.inspect(edit_info))
    error(error_msg)
  end
end

---Normalize status to simplified system (pending -> accepted)
---@param status string Original status
---@return string Normalized status ("accepted" or "rejected")
local function normalize_status(status)
  if status == "rejected" then
    return "rejected"
  else
    return "accepted"
  end
end

---Generate a unique edit operation ID
---@param chat CodeCompanion.Chat
---@return string Unique edit ID
local function generate_edit_id(chat)
  chat.edit_tracker.edit_counter = chat.edit_tracker.edit_counter + 1
  local edit_id = string.format("edit_%d_%d", chat.id, chat.edit_tracker.edit_counter)
  log:trace("[EditTracker] Generated edit ID: %s", edit_id)
  return edit_id
end

---Register a new edit operation
---@param chat CodeCompanion.Chat
---@param edit_info table Edit information
---@return string edit_id The unique ID of this edit operation
function EditTracker.register_edit_operation(chat, edit_info)
  EditTracker.init(chat)

  if not chat.edit_tracker.enabled then
    log:debug("[EditTracker] Edit tracking disabled for chat %d, skipping registration", chat.id)
    return ""
  end
  if not edit_info.tool_name then
    log:error("[EditTracker] Missing required field: tool_name")
    error("tool_name is required for edit registration")
  end
  if not edit_info.original_content then
    log:error("[EditTracker] Missing required field: original_content")
    error("original_content is required for edit registration")
  end
  local key = generate_key(edit_info)
  local tracked = chat.edit_tracker.tracked_files
  local current_timestamp = vim.loop.hrtime()

  -- Initialize tracked file if this is the first edit
  if not tracked[key] then
    log:info("[EditTracker] First edit operation for: %s", key)
    tracked[key] = {
      type = edit_info.bufnr and "buffer" or "file",
      filepath = edit_info.filepath,
      bufnr = edit_info.bufnr,
      edit_operations = {},
      first_edit_timestamp = current_timestamp,
      last_edit_timestamp = current_timestamp,
    }
  else
    log:debug("[EditTracker] Additional edit operation for: %s", key)
    tracked[key].last_edit_timestamp = current_timestamp
  end

  -- Check for duplicate edits within a short time window (1 second)
  local time_window = 1000000000 -- 1 second in nanoseconds
  for _, existing_op in ipairs(tracked[key].edit_operations) do
    local time_diff = math.abs(current_timestamp - existing_op.timestamp)
    if
      time_diff < time_window
      and existing_op.tool_name == edit_info.tool_name
      and DiffUtils.contents_equal(existing_op.original_content, edit_info.original_content)
    then
      log:debug("[EditTracker] Duplicate edit detected within %dms, skipping registration", time_diff / 1000000)
      log:debug("[EditTracker] Existing operation: %s, New tool: %s", existing_op.id, edit_info.tool_name)
      return existing_op.id -- Return existing ID
    end
  end

  -- Create edit operation (auto-convert pending to accepted)
  local edit_id = generate_edit_id(chat)
  local initial_status = edit_info.status or "accepted" -- Default to accepted instead of pending
  local edit_operation = {
    id = edit_id,
    timestamp = current_timestamp,
    tool_name = edit_info.tool_name,
    original_content = vim.deepcopy(edit_info.original_content),
    new_content = edit_info.new_content and vim.deepcopy(edit_info.new_content) or nil,
    status = normalize_status(initial_status),
    diff_id = edit_info.diff_id,
    metadata = edit_info.metadata and vim.deepcopy(edit_info.metadata) or {},
  }

  table.insert(tracked[key].edit_operations, edit_operation)

  return edit_id
end

---Update the status of an edit operation
---@param chat CodeCompanion.Chat
---@param edit_id string The edit operation ID
---@param status "accepted"|"rejected" New status
---@param new_content? string[] Updated content (optional)
---@return boolean success Whether the update was successful
function EditTracker.update_edit_status(chat, edit_id, status, new_content)
  if not chat.edit_tracker then
    log:error("[EditTracker] Edit tracker not initialized for chat %d", chat.id)
    return false
  end
  status = normalize_status(status)

  if not vim.tbl_contains({ "accepted", "rejected" }, status) then
    log:error("[EditTracker] Invalid normalized status: %s. Must be 'accepted' or 'rejected'", status)
    return false
  end
  local found_operation = nil
  local found_key = nil
  for key, tracked_file in pairs(chat.edit_tracker.tracked_files) do
    for _, operation in ipairs(tracked_file.edit_operations) do
      if operation.id == edit_id then
        found_operation = operation
        found_key = key
        break
      end
    end
    if found_operation then
      break
    end
  end
  if not found_operation then
    log:error("[EditTracker] Edit operation not found: %s", edit_id)
    return false
  end
  local _ = found_operation.status
  found_operation.status = status

  if new_content then
    found_operation.new_content = vim.deepcopy(new_content)
    log:debug("[EditTracker] Updated content for edit %s (lines: %d)", edit_id, #new_content)
  end

  return true
end

---Get a specific edit operation by ID
---@param chat CodeCompanion.Chat
---@param edit_id string The edit operation ID
---@return CodeCompanion.EditOperation|nil, string|nil
function EditTracker.get_edit_operation(chat, edit_id)
  if not chat.edit_tracker then
    log:debug("[EditTracker] Edit tracker not initialized for chat %d", chat.id)
    return nil, nil
  end
  for key, tracked_file in pairs(chat.edit_tracker.tracked_files) do
    for _, operation in ipairs(tracked_file.edit_operations) do
      if operation.id == edit_id then
        log:trace("[EditTracker] Found edit operation %s in %s", edit_id, key)
        return operation, key
      end
    end
  end
  log:debug("[EditTracker] Edit operation not found: %s", edit_id)
  return nil, nil
end

---Get all edit operations for a specific file/buffer
---@param chat CodeCompanion.Chat
---@param filepath_or_bufnr string|number File path or buffer number
---@return CodeCompanion.EditOperation[] operations
function EditTracker.get_edit_operations_for_file(chat, filepath_or_bufnr)
  if not chat.edit_tracker then
    log:debug("[EditTracker] Edit tracker not initialized for chat %d", chat.id)
    return {}
  end
  local key
  if type(filepath_or_bufnr) == "string" then
    local p = Path:new(filepath_or_bufnr)
    key = "file:" .. p:expand()
  else
    key = "buffer:" .. filepath_or_bufnr
  end
  local tracked_file = chat.edit_tracker.tracked_files[key]
  if not tracked_file then
    log:debug("[EditTracker] No tracked operations for: %s", key)
    return {}
  end
  return tracked_file.edit_operations
end

---Get all tracked edits for a chat session
---@param chat CodeCompanion.Chat
---@return table tracked_files
function EditTracker.get_tracked_edits(chat)
  if not chat.edit_tracker then
    log:debug("[EditTracker] Edit tracker not initialized for chat %d", chat.id)
    return {}
  end
  local count = vim.tbl_count(chat.edit_tracker.tracked_files)
  log:debug("[EditTracker] Returning %d tracked files for chat %d", count, chat.id)
  return chat.edit_tracker.tracked_files
end

---Get comprehensive edit statistics
---@param chat CodeCompanion.Chat
---@return table stats
function EditTracker.get_edit_stats(chat)
  if not chat.edit_tracker then
    return {
      total_files = 0,
      total_operations = 0,
      pending_operations = 0,
      accepted_operations = 0,
      rejected_operations = 0,
      tools_used = {},
    }
  end
  local stats = {
    total_files = 0,
    total_operations = 0,
    pending_operations = 0,
    accepted_operations = 0,
    rejected_operations = 0,
    tools_used = {},
  }
  for _, tracked_file in pairs(chat.edit_tracker.tracked_files) do
    stats.total_files = stats.total_files + 1
    for _, operation in ipairs(tracked_file.edit_operations) do
      stats.total_operations = stats.total_operations + 1
      if operation.status == "accepted" then
        stats.accepted_operations = stats.accepted_operations + 1
      elseif operation.status == "rejected" then
        stats.rejected_operations = stats.rejected_operations + 1
      else
        -- Fallback for any old pending status
        log:warn("[EditTracker] Found unexpected status: %s, treating as accepted", operation.status)
        stats.accepted_operations = stats.accepted_operations + 1
      end
      if not vim.tbl_contains(stats.tools_used, operation.tool_name) then
        table.insert(stats.tools_used, operation.tool_name)
      end
    end
  end
  log:debug("[EditTracker] Edit stats for chat %d: %s", chat.id, vim.inspect(stats))
  return stats
end

---Clear all tracked edits (called when chat permanently closes)
---@param chat CodeCompanion.Chat
---@return nil
function EditTracker.clear(chat)
  if chat.edit_tracker then
    EditTracker.get_edit_stats(chat)
    chat.edit_tracker.tracked_files = {}
    chat.edit_tracker.edit_counter = 0
  end
end

---Handle chat closing with pending edits
---@param chat CodeCompanion.Chat
---@return nil
function EditTracker.handle_chat_close(chat)
  if not chat.edit_tracker then
    return
  end
  local stats = EditTracker.get_edit_stats(chat)
  if stats.pending_operations == 0 then
    return
  end
  log:info("[EditTracker] Auto-accepting all pending operations for closing chat")
  for _, tracked_file in pairs(chat.edit_tracker.tracked_files) do
    for _, operation in ipairs(tracked_file.edit_operations) do
      if operation.status == "pending" then
        EditTracker.update_edit_status(chat, operation.id, "accepted", operation.new_content)
      end
    end
  end
end

---Start monitoring a tool execution
---@param tool_name string Name of the tool being executed
---@param chat CodeCompanion.Chat Chat instance
---@param tool_args? table Tool arguments (optional, for context)
---@return nil
function EditTracker.start_tool_monitoring(tool_name, chat, tool_args)
  EditTracker.init(chat)

  if not chat.edit_tracker.enabled then
    log:debug("[EditTracker] Edit tracking disabled for chat %d, skipping tool monitoring", chat.id)
    return
  end
  log:info("[EditTracker] Starting tool monitoring for: %s", tool_name)
  local target_files = {}
  local buffer_snapshots = {}
  if tool_args and tool_args.filepath then
    local filepath = vim.fs.joinpath(vim.fn.getcwd(), tool_args.filepath)
    filepath = vim.fs.normalize(filepath)

    log:debug("[EditTracker] Target file from args: %s", filepath)
    local bufnr = vim.fn.bufnr(filepath)
    if bufnr ~= -1 and api.nvim_buf_is_loaded(bufnr) then
      local content = api.nvim_buf_get_lines(bufnr, 0, -1, false)
      buffer_snapshots[filepath] = {
        bufnr = bufnr,
        content = vim.deepcopy(content),
        lines_count = #content,
      }
      log:debug("[EditTracker] Monitoring target buffer %d: %s (%d lines)", bufnr, filepath, #content)
    elseif vim.fn.filereadable(filepath) == 1 then
      local content = vim.fn.readfile(filepath)
      target_files[filepath] = {
        content = vim.deepcopy(content),
        lines_count = #content,
      }
      log:debug("[EditTracker] Monitoring target file: %s (%d lines)", filepath, #content)
    else
      -- File doesn't exist yet (e.g., create_file tool)
      target_files[filepath] = {
        content = {},
        lines_count = 0,
      }
      log:debug("[EditTracker] Monitoring non-existent target file: %s (will be created)", filepath)
    end
  else
    -- Fallback: monitor all loaded buffers if no specific target
    log:debug("[EditTracker] No target filepath in args, monitoring all loaded buffers")
    for _, bufnr in ipairs(api.nvim_list_bufs()) do
      if api.nvim_buf_is_loaded(bufnr) and api.nvim_buf_is_valid(bufnr) then
        local filepath = api.nvim_buf_get_name(bufnr)
        if filepath ~= "" and vim.fn.filereadable(filepath) == 1 then
          local content = api.nvim_buf_get_lines(bufnr, 0, -1, false)
          buffer_snapshots[filepath] = {
            bufnr = bufnr,
            content = vim.deepcopy(content),
            lines_count = #content,
          }
          log:trace("[EditTracker] Monitoring buffer %d: %s (%d lines)", bufnr, filepath, #content)
        end
      end
    end
  end

  -- Store monitoring state in chat
  if not chat._tool_monitors then
    chat._tool_monitors = {}
  end

  chat._tool_monitors[tool_name] = {
    start_time = vim.loop.hrtime(),
    buffer_snapshots = buffer_snapshots,
    target_files = target_files,
    monitoring = true,
    monitored_files_count = vim.tbl_count(buffer_snapshots) + vim.tbl_count(target_files),
    tool_args = tool_args,
  }

  log:debug(
    "[EditTracker] Tool monitoring setup complete: %d buffers, %d target files",
    vim.tbl_count(buffer_snapshots),
    vim.tbl_count(target_files)
  )
end

---Finish monitoring and detect changes for a tool
---@param tool_name string Name of the tool that finished
---@param chat CodeCompanion.Chat Chat instance
---@param success boolean Whether the tool execution was successful
---@return number detected_changes Number of changes detected
function EditTracker.finish_tool_monitoring(tool_name, chat, success)
  if not chat._tool_monitors or not chat._tool_monitors[tool_name] then
    log:debug("[EditTracker] No active monitoring for tool: %s", tool_name)
    return 0
  end
  local monitor = chat._tool_monitors[tool_name]
  log:info("[EditTracker] Finishing monitoring and detecting changes for tool: %s", tool_name)
  if not success then
    log:debug("[EditTracker] Tool %s reported failure, skipping change detection", tool_name)
    chat._tool_monitors[tool_name] = nil
    return 0
  end

  local detected_edits = 0
  local detection_results = {
    buffer_changes = {},
    file_changes = {},
    errors = {},
  }

  -- Check for buffer changes
  for filepath, snapshot in pairs(monitor.buffer_snapshots) do
    local current_success, current_content = pcall(function()
      if api.nvim_buf_is_valid(snapshot.bufnr) then
        return api.nvim_buf_get_lines(snapshot.bufnr, 0, -1, false)
      end
      return nil
    end)

    if current_success and current_content then
      if not EditTracker._content_equal(snapshot.content, current_content) then
        -- Register this edit
        local edit_id = EditTracker.register_edit_operation(chat, {
          bufnr = snapshot.bufnr,
          filepath = filepath,
          tool_name = tool_name,
          original_content = snapshot.content,
          new_content = current_content,
          metadata = {
            explanation = string.format("Auto-detected changes in %s", vim.fn.fnamemodify(filepath, ":t")),
            auto_detected = true,
            detection_method = "buffer_monitoring",
            lines_changed = math.abs(#current_content - #snapshot.content),
            tool_execution_time = vim.loop.hrtime() - monitor.start_time,
          },
        })

        if edit_id then
          detected_edits = detected_edits + 1
          table.insert(detection_results.buffer_changes, {
            filepath = filepath,
            edit_id = edit_id,
            lines_before = #snapshot.content,
            lines_after = #current_content,
          })

          -- Fire event for auto-detected edit
          utils.fire("CodeCompanionEditRegistered", {
            chat_id = chat.id,
            edit_id = edit_id,
            tool_name = tool_name,
            auto_detected = true,
            filepath = filepath,
            timestamp = vim.loop.hrtime(),
          })
        end
      else
        log:trace("[EditTracker] No changes in buffer: %s", filepath)
      end
    else
      table.insert(detection_results.errors, {
        filepath = filepath,
        error = "Failed to read current buffer content",
      })
    end
  end

  -- Check for target file changes (files not in buffers)
  for filepath, snapshot in pairs(monitor.target_files or {}) do
    local current_success, current_content = pcall(function()
      if vim.fn.filereadable(filepath) == 1 then
        return vim.fn.readfile(filepath)
      elseif snapshot.lines_count == 0 then
        -- File was expected to be created and doesn't exist yet
        return nil
      end
      return nil
    end)

    local file_was_created = snapshot.lines_count == 0 and current_success and current_content
    local file_was_modified = current_success
      and current_content
      and not EditTracker._content_equal(snapshot.content, current_content)
    if file_was_created or file_was_modified then
      local change_type = file_was_created and "created" or "modified"

      -- Register this edit
      local edit_id = EditTracker.register_edit_operation(chat, {
        filepath = filepath,
        tool_name = tool_name,
        original_content = snapshot.content,
        new_content = current_content or {},
        metadata = {
          explanation = string.format("Auto-detected %s in %s", change_type, vim.fn.fnamemodify(filepath, ":t")),
          auto_detected = true,
          detection_method = "target_file_monitoring",
          lines_changed = current_content and math.abs(#current_content - #snapshot.content) or 0,
          tool_execution_time = vim.loop.hrtime() - monitor.start_time,
          change_type = change_type,
        },
      })
      if edit_id then
        detected_edits = detected_edits + 1
        table.insert(detection_results.file_changes, {
          filepath = filepath,
          edit_id = edit_id,
          lines_before = #snapshot.content,
          lines_after = current_content and #current_content or 0,
          change_type = change_type,
        })

        utils.fire("CodeCompanionEditRegistered", {
          chat_id = chat.id,
          edit_id = edit_id,
          tool_name = tool_name,
          auto_detected = true,
          filepath = filepath,
          timestamp = vim.loop.hrtime(),
        })
      end
    elseif not current_success then
      table.insert(detection_results.errors, {
        filepath = filepath,
        error = "Failed to read current file content",
      })
    end
  end

  -- Clean up monitoring state
  chat._tool_monitors[tool_name] = nil

  -- Report results
  if detected_edits > 0 then
    local notification = string.format("🔍 Auto-detected %d file changes from %s", detected_edits, tool_name)
    vim.notify(notification, vim.log.levels.INFO)
    -- Fire summary event
    utils.fire("CodeCompanionAutoDetectionComplete", {
      chat_id = chat.id,
      tool_name = tool_name,
      detected_edits = detected_edits,
      results = detection_results,
      timestamp = vim.loop.hrtime(),
    })
  else
    log:debug("[EditTracker] No file changes detected for tool: %s", tool_name)
  end
  if #detection_results.errors > 0 then
    log:warn("[EditTracker] %d errors during auto-detection for tool %s", #detection_results.errors, tool_name)
  end

  return detected_edits
end

---Check if two content arrays are equal
---@param content1 string[]
---@param content2 string[]
---@return boolean
function EditTracker._content_equal(content1, content2)
  if #content1 ~= #content2 then
    return false
  end
  for i = 1, #content1 do
    if content1[i] ~= content2[i] then
      return false
    end
  end
  return true
end

return EditTracker
