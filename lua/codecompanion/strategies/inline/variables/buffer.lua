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
  local ok, content = pcall(buf_utils.get_content, self.context.bufnr)

  if not ok then
    return
  end

  return string.format(
    [[To help you assist with my user prompt, I'm attaching the contents of a buffer:

```%s
%s
```]],
    self.context.filetype,
    content
  )
end

return Buffer
