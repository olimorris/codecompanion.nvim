local config = require("codecompanion.config")
local context_utils = require("codecompanion.utils.context")
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
    target = args.target,
  }, { __index = EditorContext })

  return self
end

---Add the current visual selection to the chat
---@return nil
function EditorContext:apply()
  local bufnr = self.Chat.buffer_context.bufnr
  local lines, start_line, _, end_line, _ = context_utils.get_visual_selection(bufnr)

  if not lines or #lines == 0 or (start_line == 0 and end_line == 0) then
    return log:warn("No visual selection found")
  end

  local filetype = self.Chat.buffer_context.filetype or ""
  local relative_path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.")

  local content = fmt(
    [[Visual selection from `%s` (lines %d-%d):

````%s
%s
````]],
    relative_path,
    start_line,
    end_line,
    filetype,
    table.concat(lines, "\n")
  )

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = content,
  }, { _meta = { source = "editor_context", tag = "selection" }, visible = false })
end

return EditorContext
