--[[
File System Monitor - Event-based file change tracking for AI tool execution

This module tracks file changes in real-time using OS-level file system events.
Unlike snapshot-based approaches, it monitors actual file system notifications
and maintains a content cache for efficient diffing.

Architecture:
- Uses vim.uv.new_fs_event() for OS-level file watching
- Async file I/O with vim.uv.fs_* functions (never blocks Neovim)
- Debounced event processing to handle rapid changes
- Content cache with "insert returns old" pattern for easy diffing

Key Design:
- Changes are registered via async file reads (non-blocking)
- stop_monitoring_async() waits for all pending operations before calling back
- Uses uv.fs_scandir() for efficient directory scanning
- Timestamp-based attribution links changes to specific tools

API Overview:
  Core Monitoring (Tool-initiated):
    - start_monitoring(tool_name, target_path, opts) -> watch_id
    - stop_monitoring_async(watch_id, callback)
    - tag_changes_in_range(start_time, end_time, tool_name, tool_args)

  Manual Watching (User-initiated):
    - watch_cwd(opts) -> watch_id
    - watch_open_buffers(opts) -> table<bufnr, watch_id>
    - watch_manual(target_path, opts) -> watch_id
    - unwatch_buffers(watch_ids, callback)

  Change Retrieval:
    - get_all_changes() -> Change[]
    - get_changes_by_tool(tool_name) -> Change[]
    - get_stats() -> stats
    - clear_changes()

Usage (Tool execution):
  local monitor = FSMonitor.new(chat)
  local watch_id = monitor:start_monitoring("edit_tool", "/path/to/file")
  -- Tool executes, files change, monitor tracks them in real-time
  monitor:tag_changes_in_range(start_time, end_time, "edit_tool", { filepath = "/path/to/file" })
  monitor:stop_monitoring_async(watch_id, function(changes)
    -- Handle changes here
  end)

Usage (Manual watching):
  local monitor = FSMonitor.new(chat)
  local watch_ids = monitor:watch_open_buffers()
  -- User edits files...
  monitor:unwatch_buffers(watch_ids, function(count)
    print("Stopped watching " .. count .. " buffers")
  end)
]]

local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local uv = vim.uv or vim.loop
local api = vim.api
local fmt = string.format

---@class CodeCompanion.FSMonitor.Change
---@field path string Relative file path
---@field kind "created"|"modified"|"deleted"|"renamed" Change type
---@field old_content? string Content before change (nil for created)
---@field new_content? string Content after change (nil for deleted)
---@field timestamp number High-resolution timestamp (nanoseconds)
---@field tool_name string Original tool name from watch (may be "workspace")
---@field tools? string[] Array of tools that caused this change (set via tagging)
---@field metadata table Additional info (file size, error messages, attribution status, etc)
---@field metadata.attribution? "confirmed"|"ambiguous"|"unknown" Path validation status
---@field metadata.original_tool? string Original tool name before tagging
---@field metadata.source? string Source of detection ("fs_monitor", "buffer_edit", etc)
---@field metadata.auto_detected? boolean Whether change was auto-detected
---@field metadata.all_tools? string[] All tools attributed to this change

---@class CodeCompanion.FSMonitor.Watch
---@field handle uv.uv_fs_event_t|nil FS event handle
---@field root_path string Root directory being watched
---@field cache table<string, string> File path -> content cache
---@field debounce_timer? uv.uv_timer_t Timer for debouncing events
---@field pending_events table<string, boolean> Files with pending events to process
---@field tool_name string Name of tool being monitored (e.g., "workspace", "edit_tool_exp")
---@field enabled boolean Whether this watch is active
---@field buffer_snapshot? string Initial buffer content for unsaved change detection
---@field monitored_bufnr? number Buffer number being monitored (if watching a single buffer)

---@class CodeCompanion.FSMonitor
---@field chat CodeCompanion.Chat Reference to chat session
---@field watches table<string, CodeCompanion.FSMonitor.Watch> Active watches by watch_id
---@field changes CodeCompanion.FSMonitor.Change[] Accumulated changes across all watches
---@field debounce_ms number Debounce delay in milliseconds
---@field max_file_size number Maximum file size to track (bytes)
---@field watch_counter number Counter for generating unique watch IDs
local FSMonitor = {}
FSMonitor.__index = FSMonitor

-- Constants
local DEBOUNCE_MS = 300 -- Wait 300ms after last event before processing
local MAX_FILE_SIZE = 1024 * 1024 * 2 -- 2MB
local MAX_PREPOPULATE_FILES = 2000 -- Limit for cache prepopulation
local MAX_DEPTH = 6 -- Limit for recursive directory scanning

---Create a new FSMonitor instance
---@param chat CodeCompanion.Chat
---@return CodeCompanion.FSMonitor
function FSMonitor.new(chat)
  local monitor = setmetatable({
    chat = chat,
    watches = {},
    changes = {},
    debounce_ms = DEBOUNCE_MS,
    max_file_size = MAX_FILE_SIZE,
    watch_counter = 0,
  }, FSMonitor)

  log:trace("[FSMonitor] Created new monitor for chat %d", chat.id)
  return monitor
end

---Generate a unique watch ID
---@param tool_name string
---@param root_path string
---@return string
function FSMonitor:_generate_watch_id(tool_name, root_path)
  self.watch_counter = self.watch_counter + 1
  return fmt("%s:%s:%d", tool_name, root_path, self.watch_counter)
end

---Get relative path from root
---@param filepath string
---@param root_path string
---@return string Relative path
function FSMonitor:_get_relative_path(filepath, root_path)
  local normalized_file = vim.fs.normalize(filepath)
  local normalized_root = vim.fs.normalize(root_path)

  -- Try to strip the root prefix
  if normalized_file:sub(1, #normalized_root) == normalized_root then
    local relative = normalized_file:sub(#normalized_root + 1)
    -- Remove leading separator
    if relative:sub(1, 1) == "/" or relative:sub(1, 1) == "\\" then
      relative = relative:sub(2)
    end
    return relative
  end

  return normalized_file
end

---Check if file should be ignored based on patterns
---@param filepath string
---@return boolean should_ignore
function FSMonitor:_should_ignore_file(filepath)
  local ignored_patterns = {
    "%.git/",
    "node_modules/",
    "%.DS_Store$",
    "%.swp$",
    "%.swo$",
    "%.tmp$",
    "%.bak$",
    "~$",
  }

  for _, pattern in ipairs(ignored_patterns) do
    if filepath:match(pattern) then
      log:trace("[FSMonitor] Ignoring file: %s (matched pattern: %s)", filepath, pattern)
      return true
    end
  end

  return false
end

---Read file content asynchronously
---@param filepath string
---@param callback fun(content: string|nil, err: string|nil)
function FSMonitor:_read_file_async(filepath, callback)
  uv.fs_open(filepath, "r", 438, function(err_open, fd)
    if err_open then
      return callback(nil, err_open)
    end

    if not fd then
      return callback(nil, "Failed to open file")
    end

    uv.fs_fstat(fd, function(err_stat, stat)
      if err_stat then
        uv.fs_close(fd)
        return callback(nil, err_stat)
      end

      if not stat then
        uv.fs_close(fd)
        return callback(nil, "Failed to get file stats")
      end

      -- Skip files that are too large
      if stat.size > self.max_file_size then
        uv.fs_close(fd)
        log:debug("[FSMonitor] Skipping large file: %s (%d bytes)", filepath, stat.size)
        return callback(nil, fmt("File too large: %d bytes", stat.size))
      end

      -- Handle empty files
      if stat.size == 0 then
        uv.fs_close(fd)
        return callback("", nil)
      end

      uv.fs_read(fd, stat.size, 0, function(err_read, data)
        uv.fs_close(fd)

        if err_read then
          return callback(nil, err_read)
        end

        callback(data or "", nil)
      end)
    end)
  end)
end

---Register a change in the changes list
---@param change CodeCompanion.FSMonitor.Change
function FSMonitor:_register_change(change)
  -- Check for duplicate changes (same file, same kind, within 1 second)
  local current_time = change.timestamp
  local duplicate = false

  for i = #self.changes, 1, -1 do
    local existing = self.changes[i]
    if existing.path == change.path and existing.kind == change.kind then
      local time_diff = current_time - existing.timestamp
      -- Within 1 second (1 billion nanoseconds)
      if time_diff < 1000000000 then
        duplicate = true
        log:trace("[FSMonitor] Skipping duplicate change for: %s", change.path)
        break
      end
      -- Only check recent changes
      if time_diff > 5000000000 then -- 5 seconds
        break
      end
    end
  end

  if not duplicate then
    table.insert(self.changes, change)
    log:debug("[FSMonitor] Registered %s: %s (tool: %s)", change.kind, change.path, change.tool_name)

    -- Fire event for real-time tracking
    utils.fire("CodeCompanionFileChanged", {
      chat_id = self.chat.id,
      path = change.path,
      kind = change.kind,
      tool_name = change.tool_name,
      timestamp = change.timestamp,
    })
  end
end

---Process a single file change
---@param watch_id string
---@param filepath string Full path to changed file
function FSMonitor:_process_file_change(watch_id, filepath)
  local watch = self.watches[watch_id]
  if not watch or not watch.enabled then
    return
  end

  -- Ignore certain files
  if self:_should_ignore_file(filepath) then
    return
  end

  local relative_path = self:_get_relative_path(filepath, watch.root_path)
  local cached_content = watch.cache[relative_path]

  -- Read current file content
  self:_read_file_async(filepath, function(new_content, err)
    vim.schedule(function()
      -- Check if watch is still active
      if not self.watches[watch_id] or not self.watches[watch_id].enabled then
        return
      end

      -- File deleted or doesn't exist
      if err and (err:match("ENOENT") or err:match("no such file")) then
        if cached_content then
          watch.cache[relative_path] = nil
          self:_register_change({
            path = relative_path,
            kind = "deleted",
            old_content = cached_content,
            new_content = nil,
            timestamp = uv.hrtime(),
            tool_name = watch.tool_name,
            metadata = {},
          })
        end
        return
      end

      -- Error reading file
      if err then
        log:warn("[FSMonitor] Failed to read file: %s, error: %s", filepath, err)
        return
      end

      -- File exists and we read it successfully
      if cached_content then
        -- File was modified - compare contents
        if cached_content ~= new_content then
          watch.cache[relative_path] = new_content
          self:_register_change({
            path = relative_path,
            kind = "modified",
            old_content = cached_content,
            new_content = new_content,
            timestamp = uv.hrtime(),
            tool_name = watch.tool_name,
            metadata = {
              old_size = #cached_content,
              new_size = #new_content,
            },
          })
        else
          log:trace("[FSMonitor] File unchanged: %s", relative_path)
        end
      else
        -- File was created (not in cache)
        watch.cache[relative_path] = new_content
        self:_register_change({
          path = relative_path,
          kind = "created",
          old_content = nil,
          new_content = new_content,
          timestamp = uv.hrtime(),
          tool_name = watch.tool_name,
          metadata = {
            size = #new_content,
          },
        })
      end
    end)
  end)
end

---Handle a file system event (debounced)
---@param watch_id string
---@param filename string Relative filename that changed
---@param events table Event info from uv
function FSMonitor:_handle_fs_event(watch_id, filename, events)
  local watch = self.watches[watch_id]
  if not watch or not watch.enabled then
    return
  end

  -- Build full path
  local full_path = vim.fs.joinpath(watch.root_path, filename)

  log:trace("[FSMonitor] FS event for: %s (events: %s)", full_path, vim.inspect(events))

  -- Mark as pending
  watch.pending_events[full_path] = true

  -- Debounce: reset timer each time we get an event
  if watch.debounce_timer then
    watch.debounce_timer:stop()
  else
    watch.debounce_timer = uv.new_timer()
  end

  -- Process all pending events after debounce delay
  watch.debounce_timer:start(self.debounce_ms, 0, function()
    vim.schedule(function()
      if not self.watches[watch_id] or not self.watches[watch_id].enabled then
        return
      end

      -- Process all pending events (async)
      local pending = vim.tbl_keys(watch.pending_events)
      watch.pending_events = {}

      log:trace("[FSMonitor] Processing %d pending events", #pending)

      for _, path in ipairs(pending) do
        self:_process_file_change(watch_id, path)
      end
    end)
  end)
end

---Prepopulate cache with existing file contents (async using fs_scandir)
---@param watch CodeCompanion.FSMonitor.Watch Watch structure
---@param target_path string File or directory path
---@param is_dir boolean
function FSMonitor:_prepopulate_cache(watch, target_path, is_dir)
  log:debug("[FSMonitor] Prepopulating cache for: %s", target_path)

  if not is_dir then
    -- Single file
    local relative_path = self:_get_relative_path(target_path, watch.root_path)
    self:_read_file_async(target_path, function(content, err)
      vim.schedule(function()
        if not err and content then
          watch.cache[relative_path] = content
          log:trace("[FSMonitor] Cached file: %s (%d bytes)", relative_path, #content)
        end
      end)
    end)
    return
  end

  -- Directory: scan for files
  local count = 0
  local function scan_dir(dir, depth)
    if count >= MAX_PREPOPULATE_FILES then
      log:warn("[FSMonitor] Prepopulation limit reached: %d files", MAX_PREPOPULATE_FILES)
      return
    end

    if depth > MAX_DEPTH then
      return
    end

    uv.fs_scandir(dir, function(err, handle)
      if err or not handle then
        return
      end

      -- REVIEW: we might not need vim.schedule here anymore
      vim.schedule(function()
        while true do
          local name, type = uv.fs_scandir_next(handle)
          if not name then
            break
          end

          if count >= MAX_PREPOPULATE_FILES then
            break
          end

          local full_path = vim.fs.joinpath(dir, name)

          if not self:_should_ignore_file(full_path) then
            if type == "file" then
              local relative_path = self:_get_relative_path(full_path, watch.root_path)
              self:_read_file_async(full_path, function(content, read_err)
                vim.schedule(function()
                  if not read_err and content then
                    watch.cache[relative_path] = content
                    log:trace("[FSMonitor] Cached file: %s", relative_path)
                  end
                end)
              end)
              count = count + 1
            elseif type == "directory" then
              scan_dir(full_path, depth + 1)
            end
          end
        end
      end)
    end)
  end

  scan_dir(target_path, 0)
  log:debug("[FSMonitor] Initiated prepopulation scan (limit: %d files)", MAX_PREPOPULATE_FILES)
end

---Start monitoring a file or directory for changes
---@param tool_name string
---@param target_path string File or directory to watch
---@param opts? table Options: { prepopulate = true, recursive = false }
---@return string watch_id
function FSMonitor:start_monitoring(tool_name, target_path, opts)
  opts = opts or {}
  local prepopulate = opts.prepopulate ~= false -- Default true
  local recursive = opts.recursive or false

  local normalized_path = vim.fs.normalize(target_path)
  local stat = uv.fs_stat(normalized_path)

  if not stat then
    log:error("[FSMonitor] Path does not exist: %s", normalized_path)
    return ""
  end

  local is_dir = stat.type == "directory"
  local root_path = is_dir and normalized_path or vim.fs.dirname(normalized_path)

  -- Check if we're already watching this path
  for existing_watch_id, watch in pairs(self.watches) do
    if watch.root_path == root_path and watch.enabled then
      log:debug(
        "[FSMonitor] Already watching path: %s (existing watch_id: %s), reusing for tool: %s",
        root_path,
        existing_watch_id,
        tool_name
      )
      return existing_watch_id
    end
  end

  local watch_id = self:_generate_watch_id(tool_name, root_path)

  log:info("[FSMonitor] Starting monitoring: %s (tool: %s, path: %s)", watch_id, tool_name, target_path)

  -- Create watch structure
  self.watches[watch_id] = {
    handle = nil,
    root_path = root_path,
    cache = {},
    debounce_timer = nil,
    pending_events = {},
    tool_name = tool_name,
    enabled = true,
  }

  local watch = self.watches[watch_id]

  if prepopulate then
    self:_prepopulate_cache(watch, normalized_path, is_dir)
  end

  watch.handle = uv.new_fs_event()
  if not watch.handle then
    log:error("[FSMonitor] Failed to create fs_event handle")
    self.watches[watch_id] = nil
    return ""
  end

  local ok, err = watch.handle:start(root_path, { recursive = recursive }, function(err_event, filename, events)
    if err_event then
      log:error("[FSMonitor] Watch error on %s: %s", watch_id, err_event)
      return
    end

    if filename then
      self:_handle_fs_event(watch_id, filename, events)
    end
  end)

  if not ok then
    log:error("[FSMonitor] Failed to start watch: %s", err)
    if watch.handle and not watch.handle:is_closing() then
      watch.handle:close()
    end
    self.watches[watch_id] = nil
    return ""
  end

  log:info("[FSMonitor] Successfully started watch: %s", watch_id)
  return watch_id
end

---Stop monitoring and return changes via callback (async, waits for all operations)
---@param watch_id string
---@param callback fun(changes: CodeCompanion.FSMonitor.Change[])
function FSMonitor:stop_monitoring_async(watch_id, callback)
  local watch = self.watches[watch_id]
  if not watch then
    log:debug("[FSMonitor] No active watch: %s", watch_id)
    return callback({})
  end

  log:info("[FSMonitor] Stopping monitoring (async): %s", watch_id)

  watch.enabled = false

  if watch.debounce_timer then
    watch.debounce_timer:stop()
    if not watch.debounce_timer:is_closing() then
      watch.debounce_timer:close()
    end
  end

  if watch.handle then
    watch.handle:stop()
    if not watch.handle:is_closing() then
      watch.handle:close()
    end
  end

  -- Gather pending events
  local pending_paths = vim.tbl_keys(watch.pending_events)
  watch.pending_events = {}

  -- No pending? Return immediately
  if #pending_paths == 0 then
    local tool_changes = self:get_changes_by_tool(watch.tool_name)
    self.watches[watch_id] = nil
    log:info("[FSMonitor] Stopped (no pending): %s (%d changes)", watch_id, #tool_changes)
    return callback(tool_changes)
  end

  -- Track async completion
  local remaining = #pending_paths
  local completed = false

  local function on_file_processed()
    remaining = remaining - 1
    log:trace("[FSMonitor] File processed, remaining: %d", remaining)

    if remaining == 0 and not completed then
      completed = true
      local tool_changes = self:get_changes_by_tool(watch.tool_name)
      self.watches[watch_id] = nil
      log:info("[FSMonitor] Stopped (async complete): %s (%d changes)", watch_id, #tool_changes)
      callback(tool_changes)
    end
  end

  -- Process all pending files asynchronously
  for _, path in ipairs(pending_paths) do
    local relative_path = self:_get_relative_path(path, watch.root_path)
    local cached_content = watch.cache[relative_path]

    self:_read_file_async(path, function(content, err)
      vim.schedule(function()
        -- File deleted or doesn't exist
        if err and (err:match("ENOENT") or err:match("no such file")) then
          if cached_content then
            watch.cache[relative_path] = nil
            self:_register_change({
              path = relative_path,
              kind = "deleted",
              old_content = cached_content,
              new_content = nil,
              timestamp = uv.hrtime(),
              tool_name = watch.tool_name,
              metadata = {},
            })
          end
        elseif not err and content then
          -- File modified
          if cached_content and cached_content ~= content then
            watch.cache[relative_path] = content
            self:_register_change({
              path = relative_path,
              kind = "modified",
              old_content = cached_content,
              new_content = content,
              timestamp = uv.hrtime(),
              tool_name = watch.tool_name,
              metadata = {
                old_size = #cached_content,
                new_size = #content,
              },
            })
          elseif not cached_content then
            -- File created
            watch.cache[relative_path] = content
            self:_register_change({
              path = relative_path,
              kind = "created",
              old_content = nil,
              new_content = content,
              timestamp = uv.hrtime(),
              tool_name = watch.tool_name,
              metadata = {
                size = #content,
              },
            })
          end
        end

        on_file_processed()
      end)
    end)
  end
end

---Stop all active watches
---@param callback fun() Called when all watches are stopped
function FSMonitor:stop_all_async(callback)
  log:info("[FSMonitor] Stopping all watches (async)")

  local watch_ids = vim.tbl_keys(self.watches)
  if #watch_ids == 0 then
    return callback()
  end

  local remaining = #watch_ids
  for _, watch_id in ipairs(watch_ids) do
    self:stop_monitoring_async(watch_id, function()
      remaining = remaining - 1
      if remaining == 0 then
        callback()
      end
    end)
  end
end

---Get all changes detected across all watches
---Returns a deep copy of all accumulated changes. Changes persist across
---stop/start cycles until explicitly cleared with clear_changes().
---@return CodeCompanion.FSMonitor.Change[] changes
function FSMonitor:get_all_changes()
  return vim.deepcopy(self.changes)
end

---Get changes for a specific tool
---Filters accumulated changes to only those tagged with the specified tool name.
---@param tool_name string
---@return CodeCompanion.FSMonitor.Change[] changes
function FSMonitor:get_changes_by_tool(tool_name)
  local tool_changes = {}
  for _, change in ipairs(self.changes) do
    if change.tool_name == tool_name then
      table.insert(tool_changes, change)
    end
  end
  return tool_changes
end

---Clear all tracked changes
function FSMonitor:clear_changes()
  log:debug("[FSMonitor] Clearing all changes")
  self.changes = {}
end

---Get statistics about tracked changes
---Returns summary statistics including counts by change type, tools used, and active watches.
---@return table stats Statistics with fields: total_changes, created, modified, deleted, renamed, tools, active_watches
function FSMonitor:get_stats()
  local stats = {
    total_changes = #self.changes,
    created = 0,
    modified = 0,
    deleted = 0,
    renamed = 0,
    tools = {},
    active_watches = vim.tbl_count(self.watches),
  }

  for _, change in ipairs(self.changes) do
    if change.kind == "created" then
      stats.created = stats.created + 1
    elseif change.kind == "modified" then
      stats.modified = stats.modified + 1
    elseif change.kind == "deleted" then
      stats.deleted = stats.deleted + 1
    elseif change.kind == "renamed" then
      stats.renamed = stats.renamed + 1
    end

    if not vim.tbl_contains(stats.tools, change.tool_name) then
      table.insert(stats.tools, change.tool_name)
    end
  end

  return stats
end

---Enable manual watching mode for chat session
---Manual mode is a flag that can be used to keep monitoring active even when no tools are running.
---This is useful for user-initiated file watching outside of tool execution.
---@return boolean success
function FSMonitor:enable_manual_mode()
  if not self.chat.fs_monitor_manual_mode then
    self.chat.fs_monitor_manual_mode = true
    log:info("[FSMonitor] Manual mode enabled for chat %d", self.chat.id)
    return true
  end
  return false
end

---Disable manual watching mode
---Clears the manual mode flag from the chat session.
---@return boolean success
function FSMonitor:disable_manual_mode()
  if self.chat.fs_monitor_manual_mode then
    self.chat.fs_monitor_manual_mode = false
    log:info("[FSMonitor] Manual mode disabled for chat %d", self.chat.id)
    return true
  end
  return false
end

---Check if manual mode is enabled
---@return boolean is_enabled
function FSMonitor:is_manual_mode()
  return self.chat.fs_monitor_manual_mode or false
end

---Start watching current working directory manually
---This is a convenience wrapper for user-initiated monitoring of the entire workspace.
---By default, watches recursively without prepopulating the cache.
---@param opts? table Options: { prepopulate = false, recursive = true }
---@return string watch_id
function FSMonitor:watch_cwd(opts)
  opts = opts or {}
  opts.prepopulate = opts.prepopulate ~= nil and opts.prepopulate or false
  opts.recursive = opts.recursive ~= nil and opts.recursive or true

  local cwd = vim.fn.getcwd()
  log:info("[FSMonitor] Manually watching CWD: %s", cwd)
  return self:start_monitoring("manual", cwd, opts)
end

---Start watching all currently open buffer files manually
---Creates individual watches for each loaded buffer with a readable file.
---Returns a map that can be passed to unwatch_buffers() to stop all watches.
---By default, prepopulates cache but doesn't watch recursively.
---@param opts? table Options: { prepopulate = true, recursive = false }
---@return table<number, string> watch_ids Map of bufnr to watch_id
function FSMonitor:watch_open_buffers(opts)
  opts = opts or {}
  opts.prepopulate = opts.prepopulate ~= nil and opts.prepopulate or true
  opts.recursive = opts.recursive or false

  local watch_ids = {}
  local buffers = api.nvim_list_bufs()

  for _, bufnr in ipairs(buffers) do
    if api.nvim_buf_is_loaded(bufnr) and api.nvim_buf_is_valid(bufnr) then
      local filepath = api.nvim_buf_get_name(bufnr)
      if filepath ~= "" and vim.fn.filereadable(filepath) == 1 then
        log:debug("[FSMonitor] Manually watching buffer %d: %s", bufnr, filepath)
        local watch_id = self:start_monitoring("manual", filepath, opts)
        if watch_id ~= "" then
          watch_ids[bufnr] = watch_id
        end
      end
    end
  end

  log:info("[FSMonitor] Started watching %d open buffers", vim.tbl_count(watch_ids))
  return watch_ids
end

---Start watching a path manually (user-initiated or external tools)
---This is a convenience wrapper for start_monitoring() with "manual" as the tool_name.
---Useful for user-initiated watching of specific files or directories.
---@param target_path string File or directory to watch
---@param opts? table Options: { prepopulate = true, recursive = false }
---@return string watch_id
function FSMonitor:watch_manual(target_path, opts)
  log:info("[FSMonitor] Manually watching: %s", target_path)
  return self:start_monitoring("manual", target_path, opts)
end

---Stop watching open buffers that were started with watch_open_buffers
---Stops all watches in the provided map asynchronously. The callback is invoked
---after all watches have been stopped, with the count of stopped watches.
---@param watch_ids table<number, string> Map from watch_open_buffers()
---@param callback? fun(count: number) Optional callback when all watches are stopped
function FSMonitor:unwatch_buffers(watch_ids, callback)
  local watch_id_list = vim.tbl_values(watch_ids)
  if #watch_id_list == 0 then
    if callback then
      callback(0)
    end
    log:info("[FSMonitor] No buffers to unwatch")
    return
  end

  local remaining = #watch_id_list
  local count = 0

  for bufnr, watch_id in pairs(watch_ids) do
    self:stop_monitoring_async(watch_id, function()
      count = count + 1
      remaining = remaining - 1
      if remaining == 0 then
        log:info("[FSMonitor] Stopped watching %d buffers", count)
        if callback then
          callback(count)
        end
      end
    end)
  end
end

---Tag changes in a time range with a tool name and validate against tool paths
---This method attributes file changes to specific tools based on timestamps and path validation.
---Changes are marked as "confirmed" if they match the tool's declared filepath, or "ambiguous" otherwise.
---@param start_time number
---@param end_time number
---@param tool_name string Tool name to tag changes with (e.g., "edit_tool_exp", "create_file")
---@param tool_args? table Tool arguments (may contain filepath for path validation)
function FSMonitor:tag_changes_in_range(start_time, end_time, tool_name, tool_args)
  tool_args = tool_args or {}

  -- Extract expected paths from tool args
  local expected_paths = {}
  if tool_args.filepath then
    local normalized = vim.fs.normalize(tool_args.filepath)
    local relative = self:_get_relative_path(normalized, vim.fn.getcwd())
    table.insert(expected_paths, relative)
  end

  local tagged_count = 0
  local ambiguous_count = 0

  for _, change in ipairs(self.changes) do
    if change.timestamp >= start_time and change.timestamp <= end_time then
      -- Initialize tools array if not exists
      if not change.tools then
        change.tools = {}
        change.metadata = change.metadata or {}
        change.metadata.original_tool = change.tool_name
      end

      -- Check if this change matches the tool's declared paths
      local matches_declared_path = false
      if #expected_paths > 0 then
        for _, expected_path in ipairs(expected_paths) do
          if change.path == expected_path or change.path:match("^" .. vim.pesc(expected_path)) then
            matches_declared_path = true
            break
          end
        end
      else
        -- Tool didn't declare a filepath (e.g., cmd_runner) - assume it might affect anything
        matches_declared_path = true
      end

      -- Tag the change with actual tool name
      if not vim.tbl_contains(change.tools, tool_name) then
        table.insert(change.tools, tool_name)
      end

      if matches_declared_path then
        change.metadata.attribution = "confirmed"
        tagged_count = tagged_count + 1
        log:trace("[FSMonitor] Tagged change %s with tool %s (confirmed)", change.path, tool_name)
      else
        -- Change happened during tool execution but doesn't match declared paths
        change.metadata.attribution = "ambiguous"
        ambiguous_count = ambiguous_count + 1
        log:trace("[FSMonitor] Tagged change %s with tool %s (ambiguous - path not declared)", change.path, tool_name)
      end
    end
  end

  log:debug(
    "[FSMonitor] Tagged %d confirmed and %d ambiguous changes for tool: %s",
    tagged_count,
    ambiguous_count,
    tool_name
  )
end

return FSMonitor
