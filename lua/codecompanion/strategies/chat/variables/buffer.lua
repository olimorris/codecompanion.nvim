local buf_utils = require("codecompanion.utils.buffers")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.Variable.Buffer: CodeCompanion.Variable
---@field new fun(args: CodeCompanion.Variable): CodeCompanion.Variable.Buffer
---@field execute fun(self: CodeCompanion.Variable.Buffer): string
local Variable = {}

---@param args CodeCompanion.Variable
function Variable.new(args)
  local self = setmetatable({
    chat = args.chat,
    params = args.params,
  }, { __index = Variable })

  return self
end

---Return the contents of the current buffer that the chat was initiated from
---@return string
function Variable:execute()
  local range
  if self.params then
    local start, finish = self.params:match("(%d+)-(%d+)")

    if start and finish then
      start = tonumber(start) - 1
      finish = tonumber(finish)
    end

    if start <= finish then
      range = { start, finish }
    end
  end

  local output = buf_utils.format_with_line_numbers(self.chat.context.bufnr, range)
  log:trace("Buffer Variable:\n---\n%s", output)

  return output
end

return Variable
