local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local fmt = string.format

---@class CodeCompanion.EditorContext.Selection: CodeCompanion.EditorContext
local EditorContext = {}

---@param args CodeCompanion.EditorContextArgs
function EditorContext.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    params = args.params,
  }, { __index = EditorContext })

  return self
end

---Add the current visual selection to the chat
---@return nil
function EditorContext:apply()
  local ctx = self.Chat.buffer_context

  if not ctx.is_visual or not ctx.lines or #ctx.lines == 0 then
    return log:warn("No visual selection found")
  end

  local relative_path = vim.fn.fnamemodify(ctx.filename, ":.")

  local content = fmt(
    [[Visual selection from `%s` (lines %d-%d):

````%s
%s
````]],
    relative_path,
    ctx.start_line,
    ctx.end_line,
    ctx.filetype or "",
    table.concat(ctx.lines, "\n")
  )

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = content,
  }, { _meta = { source = "editor_context", tag = "selection" }, visible = false })
end

return EditorContext
