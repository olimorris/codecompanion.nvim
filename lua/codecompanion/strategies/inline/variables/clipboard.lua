---@class CodeCompanion.Inline.Variables.ClipBoard: CodeCompanion.Inline.Variables
local ClipBoard = {}

---@param args CodeCompanion.Inline.VariablesArgs
function ClipBoard.new(args)
  return setmetatable({
    context = args.context,
  }, { __index = ClipBoard })
end

---Fetch and output a buffer's contents
---@return string|nil
function ClipBoard:output()
  local content = vim.fn.getreg("+")
  if content == "" then
    content = vim.fn.getreg("*")
  end

  return string.format(
    [[Sharing the contents of my clipboard:

<clipboard>%s</clipboard>]],
    content
  )
end

return ClipBoard
