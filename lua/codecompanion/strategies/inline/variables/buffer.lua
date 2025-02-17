---@class CodeCompanion.Inline.Varible.Buffer: CodeCompanion.Variables
local Buffer = {}

---@param args table
function Buffer.new(args)
  return setmetatable({
    context = args.context,
  }, { __index = Buffer })
end

---Fetch and output a buffer's contents
---@return table
function Buffer:output() end

return Buffer
