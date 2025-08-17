local buf_utils = require("codecompanion.utils.buffers")

---@class CodeCompanion.Inline.Variables.Buffer: CodeCompanion.Inline.Variables
local Buffer = {}

---@param args CodeCompanion.Inline.VariablesArgs
function Buffer.new(args)
  return setmetatable({
    context = args.context,
  }, { __index = Buffer })
end

---Fetch and output a buffer's contents
---@return string|nil
function Buffer:output()
  local message = "To help you assist with my user prompt, I'm attaching the contents of a buffer"

  local ok, content, _, _ = pcall(buf_utils.format_for_llm, {
    bufnr = self.context.bufnr,
    path = buf_utils.get_info(self.context.bufnr).path,
  }, { message = message })

  if not ok then
    return
  end

  return content
end

return Buffer
