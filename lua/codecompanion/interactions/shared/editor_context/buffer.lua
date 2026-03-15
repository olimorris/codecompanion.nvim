local buf_utils = require("codecompanion.utils.buffers")
local chat_helpers = require("codecompanion.interactions.chat.helpers")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local reserved_params = {
  "all",
  "diff",
}

---@class CodeCompanion.EditorContext.Buffer: CodeCompanion.EditorContext
local EditorContext = {}

---@param args CodeCompanion.EditorContextArgs
function EditorContext.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    buffer_context = args.buffer_context or (args.Chat and args.Chat.buffer_context),
    config = args.config,
    params = args.params,
    target = args.target,
  }, { __index = EditorContext })

  return self
end

---Find buffer by display option (filename, relative path, etc.) - Static version
---@param target string
---@return number|nil
function EditorContext._find_buffer(target)
  local open_buffers = buf_utils.get_open()

  for _, buf_info in ipairs(open_buffers) do
    if buf_info.name == target then
      return buf_info.bufnr
    end
    if buf_info.path == target then
      return buf_info.bufnr
    end
    if buf_info.short_path == target then
      return buf_info.bufnr
    end
  end

  -- Try to find by path even if not loaded
  return buf_utils.get_bufnr_from_path(target)
end

---Find buffer by display option (filename, relative path, etc.) - Instance method
---@param target string
---@return number|nil
function EditorContext:find_buffer(target)
  return EditorContext._find_buffer(target)
end

---Add the contents of the current buffer to the chat
---@param selected table
---@param opts? table
---@return nil
function EditorContext:chat_render(selected, opts)
  selected = selected or {}
  opts = opts or {}

  local bufnr = selected.bufnr or _G.codecompanion_current_context or self.Chat.buffer_context.bufnr
  local params = selected.params or self.params

  if self.target then
    local found = self:find_buffer(self.target)
    if found then
      bufnr = found
      log:debug("Found buffer %d for display option: %s", bufnr, self.target)
    else
      return log:warn("Could not find buffer for display option: %s", self.target)
    end
  end

  if params and not vim.tbl_contains(reserved_params, params) then
    return log:warn("Invalid parameter for buffer editor context: %s", params)
  end

  local message = "User's current visible code in a file (including line numbers). This should be the main focus"
  if opts.sync_all then
    message = "Here is the updated file content (including line numbers)"
  end

  local buf_info = buf_utils.get_info(bufnr)

  local ok, content, id, _ = pcall(chat_helpers.format_buffer_for_llm, bufnr, buf_info.path, { message = message })
  if not ok then
    return log:warn(content)
  end

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = content,
  }, {
    _meta = { source = "editor_context", tag = "buffer" },
    context = { id = id, path = buf_info.path },
    visible = false,
  })

  if opts.sync_all then
    return
  end

  self.Chat.context:add({
    bufnr = bufnr,
    params = params,
    id = id,
    opts = {
      sync_all = (params and params == "all"),
      sync_diff = (params and params == "diff"),
    },
    source = "codecompanion.interactions.shared.editor_context.buffer",
  })
end

-- Alias for sync_all_buffer_content compatibility (shared interface with slash commands)
EditorContext.output = EditorContext.chat_render

---Return inline label for the CLI interaction
---@return { inline: string }|nil
function EditorContext:cli_render()
  local bufnr = self.buffer_context and self.buffer_context.bufnr

  if self.target then
    local found = self:find_buffer(self.target)
    if found then
      bufnr = found
    else
      log:warn("Could not find buffer for display option: %s", self.target)
      return nil
    end
  end

  if not bufnr then
    return nil
  end

  local relative_path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.")
  return {
    inline = string.format("@%s", relative_path),
  }
end

---Replace the editor context in the message
---@param prefix string
---@param message string
---@param bufnr number
---@return string
function EditorContext.replace(prefix, message, bufnr)
  local result = message

  -- Handle #{buffer:filename}{param} - display option with parameters
  local display = prefix .. "{buffer:([^}]*)}{[^}]*}"
  result = result:gsub(display, function(target)
    local found_bufnr = EditorContext._find_buffer(target)
    if found_bufnr then
      local path = buf_utils.get_info(found_bufnr).path
      return "file `" .. path .. "` (with buffer number: " .. found_bufnr .. ")"
    else
      -- Fallback to original behavior if buffer not found
      local path = buf_utils.get_info(bufnr).path
      return "file `" .. path .. "` (with buffer number: " .. bufnr .. ")"
    end
  end)

  -- Handle #{buffer:filename} - Just display option
  local display_option_pattern = prefix .. "{buffer:([^}]*)}"
  result = result:gsub(display_option_pattern, function(target)
    local found_bufnr = EditorContext._find_buffer(target)
    if found_bufnr then
      local path = buf_utils.get_info(found_bufnr).path
      return "file `" .. path .. "` (with buffer number: " .. found_bufnr .. ")"
    else
      -- Fallback to original behavior if buffer not found
      local path = buf_utils.get_info(bufnr).path
      return "file `" .. path .. "` (with buffer number: " .. bufnr .. ")"
    end
  end)

  -- Finally handle #{buffer}
  local path = buf_utils.get_info(bufnr).path
  local replacement = "file `" .. path .. "` (with buffer number: " .. bufnr .. ")"

  result = result:gsub(prefix .. "{buffer}{[^}]*}", replacement)
  result = result:gsub(prefix .. "{buffer}", replacement)

  return result
end

return EditorContext
