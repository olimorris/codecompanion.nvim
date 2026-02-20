local buf_utils = require("codecompanion.utils.buffers")
local chat_helpers = require("codecompanion.interactions.chat.helpers")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.EditorContext.ViewPort: CodeCompanion.EditorContext
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

---Share the visible lines in the editor's viewport as per-buffer messages
---@return nil
function EditorContext:apply()
  local excluded = self.config.opts and self.config.opts.excluded
  local buf_lines = buf_utils.get_visible_lines(excluded)

  local count = 0
  for bufnr, ranges in pairs(buf_lines) do
    for _, range in ipairs(ranges) do
      local content, id = chat_helpers.format_viewport_range_for_llm(bufnr, range)
      self.Chat:add_message({
        role = config.constants.USER_ROLE,
        content = content,
      }, {
        _meta = { source = "editor_context", tag = "viewport" },
        context = { id = id },
        visible = false,
      })
      count = count + 1
    end
  end

  if count == 0 then
    log:warn("No visible buffers to share")
  end
end

return EditorContext
