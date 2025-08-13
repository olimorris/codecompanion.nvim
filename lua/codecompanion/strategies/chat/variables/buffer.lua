local buf_utils = require("codecompanion.utils.buffers")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local reserved_params = {
  "pin",
  "watch",
}

---@class CodeCompanion.Variable.Buffer: CodeCompanion.Variable
local Variable = {}

---@param args CodeCompanion.VariableArgs
function Variable.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    params = args.params,
    target = args.target,
  }, { __index = Variable })

  return self
end

---Find buffer by display option (filename, relative path, etc.) - Static version
---@param target string
---@return number|nil
function Variable._find_buffer(target)
  local open_buffers = buf_utils.get_open()

  for _, buf_info in ipairs(open_buffers) do
    -- Check exact filename match
    if buf_info.name == target then
      return buf_info.bufnr
    end
    -- Check relative path match
    if buf_info.relative_path == target then
      return buf_info.bufnr
    end
    -- Check short path match
    if buf_info.short_path == target then
      return buf_info.bufnr
    end
  end

  -- Try to find by filepath even if not loaded
  return buf_utils.get_bufnr_from_filepath(target)
end

---Find buffer by display option (filename, relative path, etc.) - Instance method
---@param target string
---@return number|nil
function Variable:find_buffer(target)
  return Variable._find_buffer(target)
end

---Add the contents of the current buffer to the chat
---@param selected table
---@param opts? table
---@return nil
function Variable:output(selected, opts)
  selected = selected or {}
  opts = opts or {}

  local bufnr = selected.bufnr or _G.codecompanion_current_context
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
    return log:warn("Invalid parameter for buffer variable: %s", params)
  end

  local message = "User's current visible code in a file (including line numbers). This should be the main focus"
  if opts.pin then
    message = "Here is the updated file content (including line numbers)"
  end

  local ok, content, id, _ = pcall(buf_utils.format_for_llm, {
    bufnr = bufnr,
    path = buf_utils.get_info(bufnr).path,
  }, { message = message })
  if not ok then
    return log:warn(content)
  end

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = content,
  }, { context_id = id, tag = "variable", visible = false })

  if opts.pin then
    return
  end

  self.Chat.context:add({
    bufnr = bufnr,
    params = params,
    id = id,
    opts = {
      pinned = (params and params == "pin"),
      watched = (params and params == "watch"),
    },
    source = "codecompanion.strategies.chat.variables.buffer",
  })
end

---Replace the variable in the message
---@param prefix string
---@param message string
---@param bufnr number
---@return string
function Variable.replace(prefix, message, bufnr)
  local result = message

  -- Handle #{buffer:filename}{param} - display option with parameters
  local display_option_with_params_pattern = prefix .. "{buffer:([^}]*)}{[^}]*}"
  result = result:gsub(display_option_with_params_pattern, function(target)
    local found = Variable._find_buffer(target)
    if found then
      local bufname = buf_utils.name_from_bufnr(found)
      return "file `" .. bufname .. "` (with buffer number: " .. found .. ")"
    else
      -- Fallback to original behavior if buffer not found
      local bufname = buf_utils.name_from_bufnr(bufnr)
      return "file `" .. bufname .. "` (with buffer number: " .. bufnr .. ")"
    end
  end)

  -- Handle #{buffer:filename} - Just display option
  local display_option_pattern = prefix .. "{buffer:([^}]*)}"
  result = result:gsub(display_option_pattern, function(target)
    local found = Variable._find_buffer(target)
    if found then
      local bufname = buf_utils.name_from_bufnr(found)
      return "file `" .. bufname .. "` (with buffer number: " .. found .. ")"
    else
      -- Fallback to original behavior if buffer not found
      local bufname = buf_utils.name_from_bufnr(bufnr)
      return "file `" .. bufname .. "` (with buffer number: " .. bufnr .. ")"
    end
  end)

  -- Finally handle #{buffer}
  local bufname = buf_utils.name_from_bufnr(bufnr)
  local replacement = "file `" .. bufname .. "` (with buffer number: " .. bufnr .. ")"

  result = result:gsub(prefix .. "{buffer}{[^}]*}", replacement)
  result = result:gsub(prefix .. "{buffer}", replacement)

  return result
end

return Variable
