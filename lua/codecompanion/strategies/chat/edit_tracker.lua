local Path = require("plenary.path")
local helpers = require("codecompanion.strategies.chat.helpers")

local diff_utils = require("codecompanion.providers.diff.utils")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local api = vim.api
local fmt = string.format

---@class CodeCompanion.Chat.EditOperation
---@field id string Unique identifier for this edit operation
---@field timestamp number High-resolution timestamp when edit was made
---@field tool_name string Name of the tool that made the edit
---@field original_content string[] Content before the edit
---@field new_content string[] Content after the edit
---@field status "pending"|"accepted"|"rejected" Current status of the edit
---@field diff_id? string|number Associated diff ID for UI tracking
---@field metadata? table Additional metadata (patch info, line ranges, etc.)

---@class CodeCompanion.Chat.TrackedFile
---@field type "buffer"|"file" Type of tracked resource
---@field filepath? string File path (for files)
---@field bufnr? number Buffer number (for buffers)
---@field edit_operations CodeCompanion.Chat.EditOperation[] Array of all edit operations
---@field first_edit_timestamp number Timestamp of first edit
---@field last_edit_timestamp number Timestamp of last edit

---@class CodeCompanion.Chat.EditTracker
---@field tracked_files table<string, CodeCompanion.Chat.TrackedFile> Map of filepath/bufnr -> tracked file info
---@field enabled boolean Whether edit tracking is enabled
---@field edit_counter number Counter for generating unique edit IDs

---@class CodeCompanion.Chat.EditTracker
local EditTracker = {}

---Initialize edit tracking for a chat session
---@param chat CodeCompanion.Chat
---@return nil
function EditTracker.init(chat)
  if chat.edit_tracker then
    log:trace("[Edit Tracker] Already initialized for chat %d", chat.id)
    return
  end
  chat.edit_tracker = {
    tracked_files = {}, -- Map of filepath/bufnr -> tracked file info
    enabled = true,
    edit_counter = 0,
    baseline_content = {}, -- Map of filepath/bufnr -> true original content
  }
  log:info("[Edit Tracker] Initialized edit tracking for chat %d", chat.id)
end

---Generate a unique key for tracking files/buffers
---@param edit_info table Must contain either filepath or bufnr
---@return string|nil Unique key for the file/buffer
local function generate_key(edit_info)
  if edit_info.filepath then
    local p = Path:new(edit_info.filepath)
    local expanded_path = p:expand()
    log:trace("[Edit Tracker] Generated file key: file:%s", expanded_path)
    return "file:" .. expanded_path
  elseif edit_info.bufnr then
    log:trace("[Edit Tracker] Generated buffer key: buffer:%d", edit_info.bufnr)
    return "buffer:" .. edit_info.bufnr
  else
    return log:error("[Edit Tracker] Edit info must have either filepath or bufnr. Received: %s", edit_info)
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
  local edit_id = fmt("edit_%d_%d", chat.id, chat.edit_tracker.edit_counter)
  log:trace("[Edit Tracker] Generated edit ID: %s", edit_id)
  return edit_id
end

---Register a new edit operation
---@param chat CodeCompanion.Chat
---@param edit_info table Edit information
---@return string edit_id The unique ID of this edit operation
function EditTracker.register_edit_operation(chat, edit_info)
  EditTracker.init(chat)

  if not chat.edit_tracker.enabled then
    log:debug("[Edit Tracker] Edit tracking disabled for chat %d, skipping registration", chat.id)
    return ""
  end
  if not edit_info.tool_name then
    log:error("[Edit Tracker] Missing required field: tool_name")
    error("tool_name is required for edit registration")
  end
  if not edit_info.original_content then
    log:error("[Edit Tracker] Missing required field: original_content")
    error("original_content is required for edit registration")
  end
  local key = generate_key(edit_info)
  local tracked = chat.edit_tracker.tracked_files
  local current_timestamp = vim.loop.hrtime()

  -- Initialize tracked file if this is the first edit
  if not tracked[key] and key then
    log:info("[Edit Tracker] First edit operation for: %s", key)
    tracked[key] = {
      type = edit_info.bufnr and "buffer" or "file",
      filepath = edit_info.filepath,
      bufnr = edit_info.bufnr,
      edit_operations = {},
      first_edit_timestamp = current_timestamp,
      last_edit_timestamp = current_timestamp,
    }
    -- Store the baseline original content (before any tools ran)
    if not chat.edit_tracker.baseline_content[key] then
      chat.edit_tracker.baseline_content[key] = vim.deepcopy(edit_info.original_content)
      log:debug("[Edit Tracker] Stored baseline content for: %s", key)
    end
  else
    log:debug("[Edit Tracker] Additional edit operation for: %s", key)
    tracked[key].last_edit_timestamp = current_timestamp
  end

  -- Check for duplicate edits within a short time window (1 second)
  local time_window = 1000000000 -- 1 second in nanoseconds
  for _, existing_op in ipairs(tracked[key].edit_operations) do
    local time_diff = math.abs(current_timestamp - existing_op.timestamp)
    if
      time_diff < time_window
      and existing_op.tool_name == edit_info.tool_name
      and diff_utils.contents_equal(existing_op.original_content, edit_info.original_content)
    then
      log:debug("[Edit Tracker] Duplicate edit detected within %dms, skipping registration", time_diff / 1000000)
      log:debug("[Edit Tracker] Existing operation: %s, New tool: %s", existing_op.id, edit_info.tool_name)
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
    log:error("[Edit Tracker] Edit tracker not initialized for chat %d", chat.id)
    return false
  end
  status = normalize_status(status)

  if not vim.tbl_contains({ "accepted", "rejected" }, status) then
    log:error("[Edit Tracker] Invalid normalized status: %s. Must be 'accepted' or 'rejected'", status)
    return false
  end
  local found_operation = nil
  for _, tracked_file in pairs(chat.edit_tracker.tracked_files) do
    for _, operation in ipairs(tracked_file.edit_operations) do
      if operation.id == edit_id then
        found_operation = operation
        break
      end
    end
    if found_operation then
      break
    end
  end
  if not found_operation then
    log:error("[Edit Tracker] Edit operation not found: %s", edit_id)
    return false
  end
  local _ = found_operation.status
  found_operation.status = status

  if new_content then
    found_operation.new_content = vim.deepcopy(new_content)
    log:debug("[Edit Tracker] Updated content for edit %s (lines: %d)", edit_id, #new_content)
  end

  return true
end

---Get a specific edit operation by ID
---@param chat CodeCompanion.Chat
---@param edit_id string The edit operation ID
---@return CodeCompanion.Chat.EditOperation|nil, string|nil
function EditTracker.get_edit_operation(chat, edit_id)
  if not chat.edit_tracker then
    log:debug("[Edit Tracker] Edit tracker not initialized for chat %d", chat.id)
    return nil, nil
  end
  for key, tracked_file in pairs(chat.edit_tracker.tracked_files) do
    for _, operation in ipairs(tracked_file.edit_operations) do
      if operation.id == edit_id then
        log:trace("[Edit Tracker] Found edit operation %s in %s", edit_id, key)
        return operation, key
      end
    end
  end
  log:debug("[Edit Tracker] Edit operation not found: %s", edit_id)
  return nil, nil
end

---Get all edit operations for a specific file/buffer
---@param chat CodeCompanion.Chat
---@param filepath_or_bufnr string|number File path or buffer number
---@return CodeCompanion.Chat.EditOperation[] operations
function EditTracker.get_edit_operations_for_file(chat, filepath_or_bufnr)
  if not chat.edit_tracker then
    log:debug("[Edit Tracker] Edit tracker not initialized for chat %d", chat.id)
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
    log:debug("[Edit Tracker] No tracked operations for: %s", key)
    return {}
  end
  return tracked_file.edit_operations
end

---Get all tracked edits for a chat session
---@param chat CodeCompanion.Chat
---@return table tracked_files
function EditTracker.get_tracked_edits(chat)
  if not chat.edit_tracker then
    log:debug("[Edit Tracker] Edit tracker not initialized for chat %d", chat.id)
    return {}
  end
  local count = vim.tbl_count(chat.edit_tracker.tracked_files)
  log:debug("[Edit Tracker] Returning %d tracked files for chat %d", count, chat.id)
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
        log:warn("[Edit Tracker] Found unexpected status: %s, treating as accepted", operation.status)
        stats.accepted_operations = stats.accepted_operations + 1
      end
      if not vim.tbl_contains(stats.tools_used, operation.tool_name) then
        table.insert(stats.tools_used, operation.tool_name)
      end
    end
  end
  log:debug("[Edit Tracker] Edit stats for chat %d: %s", chat.id, vim.inspect(stats))
  return stats
end

---Clear all tracked edits (called when chat permanently closes)
---@param chat CodeCompanion.Chat
---@return nil
function EditTracker.clear(chat)
  log:info("[Edit Tracker] Clearing all tracked edits for chat %d", chat.id)
  if chat.edit_tracker then
    log:debug("[Edit Tracker] Clearing tracked edits for chat %d", chat.id)
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
  log:info("[Edit Tracker] Auto-accepting all pending operations for closing chat")
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
    return log:debug("[Edit Tracker] Edit tracking disabled for chat %d, skipping tool monitoring", chat.id)
  end
  log:info("[Edit Tracker] Starting tool monitoring for: %s", tool_name)
  local target_files = {}
  local buffer_snapshots = {}
  if tool_args and tool_args.filepath then
    log:debug("[Edit Tracker] Tool args provided, file path is: %s", tool_args.filepath)
    local filepath = helpers.validate_and_normalize_filepath(tool_args.filepath)

    if filepath then
      log:debug("[Edit Tracker] Target file from args: %s", filepath)
      local bufnr = vim.fn.bufnr(filepath)
      if bufnr ~= -1 and api.nvim_buf_is_loaded(bufnr) then
        local content = api.nvim_buf_get_lines(bufnr, 0, -1, false)
        buffer_snapshots[filepath] = {
          bufnr = bufnr,
          content = vim.deepcopy(content),
          lines_count = #content,
        }
        log:debug("[Edit Tracker] Monitoring target buffer %d: %s (%d lines)", bufnr, filepath, #content)
      elseif vim.fn.filereadable(filepath) == 1 then
        local content = vim.fn.readfile(filepath)
        target_files[filepath] = {
          content = vim.deepcopy(content),
          lines_count = #content,
        }
        log:debug("[Edit Tracker] Monitoring target file: %s (%d lines)", filepath, #content)
      else
        target_files[filepath] = {
          content = {},
          lines_count = 0,
        }
        log:debug("[Edit Tracker] Monitoring non-existent target file: %s (will be created)", filepath)
      end
    else
      -- Fallback: monitor all loaded buffers if no specific target
      log:debug("[Edit Tracker] No target filepath in args, monitoring all loaded buffers")
      for _, bufnr in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_loaded(bufnr) and api.nvim_buf_is_valid(bufnr) then
          filepath = api.nvim_buf_get_name(bufnr)
          if filepath ~= "" and vim.fn.filereadable(filepath) == 1 then
            local content = api.nvim_buf_get_lines(bufnr, 0, -1, false)
            buffer_snapshots[filepath] = {
              bufnr = bufnr,
              content = vim.deepcopy(content),
              lines_count = #content,
            }
            log:trace("[Edit Tracker] Monitoring buffer %d: %s (%d lines)", bufnr, filepath, #content)
          end
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
    "[Edit Tracker] Tool monitoring setup complete: %d buffers, %d target files",
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
    log:debug("[Edit Tracker] No active monitoring for tool: %s", tool_name)
    return 0
  end
  local monitor = chat._tool_monitors[tool_name]
  log:info(
    "[Edit Tracker] Finishing monitoring and detecting changes for tool: %s (success=%s)",
    tool_name,
    tostring(success)
  )

  -- Don't skip change detection for rejected tools - we want to track them
  -- Only skip for actual errors where no meaningful changes were made
  -- For now, we'll detect changes for all cases and let the status be determined later

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
            explanation = fmt("Auto-detected changes in %s", vim.fn.fnamemodify(filepath, ":t")),
            auto_detected = true,
            detection_method = "buffer_monitoring",
            lines_changed = math.abs(#current_content - #snapshot.content),
            tool_execution_time = vim.loop.hrtime() - monitor.start_time,
          },
        })

        -- Mark as rejected if tool was not successful (rejected by user)
        if edit_id and not success then
          log:debug("[Edit Tracker] Marking edit %s as rejected for tool %s", edit_id, tool_name)
          EditTracker.update_edit_status(chat, edit_id, "rejected")
          log:debug("[Edit Tracker] Edit %s status updated to rejected", edit_id)
        end

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
        log:trace("[Edit Tracker] No changes in buffer: %s", filepath)
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
          explanation = fmt("Auto-detected %s in %s", change_type, vim.fn.fnamemodify(filepath, ":t")),
          auto_detected = true,
          detection_method = "target_file_monitoring",
          lines_changed = current_content and math.abs(#current_content - #snapshot.content) or 0,
          tool_execution_time = vim.loop.hrtime() - monitor.start_time,
          change_type = change_type,
        },
      })

      -- Mark as rejected if tool was not successful (rejected by user)
      if edit_id and not success then
        log:debug("[Edit Tracker] Marking file edit %s as rejected for tool %s", edit_id, tool_name)
        EditTracker.update_edit_status(chat, edit_id, "rejected")
        log:debug("[Edit Tracker] File edit %s status updated to rejected", edit_id)
      end
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

  chat._tool_monitors[tool_name] = nil

  -- Report results
  if detected_edits > 0 then
    log:debug(
      "[Edit Tracker] %d file changes detected for tool: %s (success=%s)",
      detected_edits,
      tool_name,
      tostring(success)
    )

    -- Debug: Log current state of all tracked edits
    local stats = EditTracker.get_edit_stats(chat)
    log:debug(
      "[Edit Tracker] Current stats after %s: %d accepted, %d rejected, %d total",
      tool_name,
      stats.accepted_operations,
      stats.rejected_operations,
      stats.total_operations
    )
  end
  if #detection_results.errors > 0 then
    log:warn("[Edit Tracker] %d errors during auto-detection for tool %s", #detection_results.errors, tool_name)
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
