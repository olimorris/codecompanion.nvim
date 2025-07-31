local Path = require("plenary.path")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.EditTracker
local EditTracker = {}

---Initialize edit tracking for a chat session
---@param chat CodeCompanion.Chat
---@return nil
function EditTracker.init(chat)
  if chat.edit_tracker then
    return
  end
  chat.edit_tracker = {
    tracked_files = {}, -- Map of filepath/bufnr -> edit info
    enabled = true,
  }
  log:debug("[EditTracker] Initialized for chat %d", chat.id)
end

---Generate a unique key for tracking
---@param edit_info table
---@return string
local function generate_key(edit_info)
  if edit_info.filepath then
    local p = Path:new(edit_info.filepath)
    return "file:" .. p:expand()
  elseif edit_info.bufnr then
    return "buffer:" .. edit_info.bufnr
  else
    error("Edit info must have either filepath or bufnr")
  end
end

---Register an edit operation
---@param chat CodeCompanion.Chat
---@param edit_info table
---@return nil
function EditTracker.register_edit(chat, edit_info)
  EditTracker.init(chat) -- Ensure initialized

  if not chat.edit_tracker.enabled then
    return
  end

  local key = generate_key(edit_info)
  local tracked = chat.edit_tracker.tracked_files

  -- First edit for this file/buffer
  if not tracked[key] then
    log:debug("[EditTracker] First edit registered for: %s", key)
    tracked[key] = {
      type = edit_info.bufnr and "buffer" or "file",
      filepath = edit_info.filepath,
      bufnr = edit_info.bufnr,
      original_content = vim.deepcopy(edit_info.original_content),
      first_edit_timestamp = vim.loop.hrtime(),
      tool_names = {},
    }
  end

  -- Update tracking info
  local file_track = tracked[key]
  file_track.last_edit_timestamp = vim.loop.hrtime()

  if edit_info.tool_name and not vim.tbl_contains(file_track.tool_names, edit_info.tool_name) then
    table.insert(file_track.tool_names, edit_info.tool_name)
  end

  log:debug("[EditTracker] Edit registered for %s by tool: %s", key, edit_info.tool_name or "unknown")
end

---Get all tracked edits for a chat session
---@param chat CodeCompanion.Chat
---@return table
function EditTracker.get_tracked_edits(chat)
  if not chat.edit_tracker then
    return {}
  end
  return chat.edit_tracker.tracked_files
end

---Clear all tracked edits (called when chat permanently closes)
---@param chat CodeCompanion.Chat
---@return nil
function EditTracker.clear(chat)
  if chat.edit_tracker then
    chat.edit_tracker.tracked_files = {}
    log:debug("[EditTracker] Cleared edits for chat %d", chat.id)
  end
end

---Check if edit tracking is enabled
---@param chat CodeCompanion.Chat
---@return boolean
function EditTracker.is_enabled(chat)
  return chat.edit_tracker and chat.edit_tracker.enabled or false
end

---Enable/disable edit tracking
---@param chat CodeCompanion.Chat
---@param enabled boolean
---@return nil
function EditTracker.set_enabled(chat, enabled)
  EditTracker.init(chat)
  chat.edit_tracker.enabled = enabled
  log:debug("[EditTracker] %s for chat %d", enabled and "Enabled" or "Disabled", chat.id)
end

return EditTracker
