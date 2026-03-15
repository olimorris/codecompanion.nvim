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
    buffer_context = args.buffer_context or (args.Chat and args.Chat.buffer_context),
    config = args.config,
    params = args.params,
  }, { __index = EditorContext })

  return self
end

---Share the visible lines in the editor's viewport as per-buffer messages
---@return nil
function EditorContext:chat_render()
  local ec_opts = config.interactions.shared.editor_context.opts
  local excluded = ec_opts and ec_opts.excluded
  local buf_lines = buf_utils.get_visible_lines(excluded)

  local count = 0
  for bufnr, ranges in pairs(buf_lines) do
    for _, range in ipairs(ranges) do
      local content = chat_helpers.format_viewport_range_for_llm(bufnr, range)
      self.Chat:add_message({
        role = config.constants.USER_ROLE,
        content = content,
      }, {
        _meta = { source = "editor_context", tag = "viewport" },
        visible = false,
      })
      count = count + 1
    end
  end

  if count == 0 then
    log:warn("No visible buffers to share")
  end
end

---Return inline label for the CLI interaction
---@return { inline: string }|nil
function EditorContext:cli_render()
  local ec_opts = config.interactions.shared.editor_context.opts
  local excluded = ec_opts and ec_opts.excluded
  local buf_lines = buf_utils.get_visible_lines(excluded)

  local paths = {}
  for bufnr, _ in pairs(buf_lines) do
    local path = buf_utils.get_info(bufnr).relative_path
    if path ~= "" then
      table.insert(paths, string.format("@%s", path))
    end
  end

  if #paths == 0 then
    log:warn("No visible buffers to share")
    return nil
  end

  return {
    inline = "the visible code in " .. table.concat(paths, ", "),
  }
end

return EditorContext
