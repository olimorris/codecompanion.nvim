local buf_utils = require("codecompanion.utils.buffers")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local fmt = string.format

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

---Read the contents of the buffer
---@param bufnr number
---@param range table
---@return string, string
function Variable:read(bufnr, range)
  local content = buf_utils.format_with_line_numbers(bufnr, range)
  log:trace("Buffer Variable:\n---\n%s", content)

  local name = self.Chat.references:make_id_from_buf(bufnr)
  if name == "" then
    name = "Buffer " .. bufnr
  end

  local id = "<buf>" .. name .. "</buf>"

  return content, id
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

  local range
  if params then
    local start, finish = params:match("(%d+)-(%d+)")

    if start and finish then
      start = tonumber(start) - 1
      finish = tonumber(finish)
    end

    if start <= finish then
      range = { start, finish }
    end
  end

  local content, id = self:read(bufnr, range)

  local message = "Here is the content from the buffer.\n\n"
  if opts.pin then
    message = "Here is the updated buffer content.\n\n"
  end

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = fmt([[%s%s]], message, content),
  }, { reference = id, tag = "variable", visible = false })

  if opts.pin then
    return
  end

  self.Chat.references:add({
    bufnr = bufnr,
    params = params,
    id = id,
    source = "codecompanion.strategies.chat.variables.buffer",
  })
end

return Variable
