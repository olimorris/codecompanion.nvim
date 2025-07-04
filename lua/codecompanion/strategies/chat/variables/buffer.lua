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
  }, { __index = Variable })

  return self
end

---Add the contents of the current buffer to the chat
---@param selected table
---@param opts? table
---@return nil
function Variable:output(selected, opts)
  selected = selected or {}
  opts = opts or {}

  local bufnr = selected.bufnr or self.Chat.context.bufnr
  local params = selected.params or self.params

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
  }, { reference = id, tag = "variable", visible = false })

  if opts.pin then
    return
  end

  self.Chat.references:add({
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
---@param message string
---@param bufnr number
---@return string
function Variable.replace(prefix, message, bufnr)
  local bufname = buf_utils.name_from_bufnr(bufnr)
  local replacement = "file `" .. bufname .. "` (with buffer number: " .. bufnr .. ")"

  local result = message:gsub(prefix .. "{buffer}{[^}]*}", replacement)
  result = result:gsub(prefix .. "{buffer}", replacement)

  return result
end

return Variable
