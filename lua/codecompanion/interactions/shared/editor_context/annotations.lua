local annotations = require("codecompanion.interactions.shared.annotations")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local tags = require("codecompanion.interactions.shared.tags")

local fmt = string.format

---@class CodeCompanion.EditorContext.Annotations: CodeCompanion.EditorContext
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

---Format an annotation into an `<annotation>` block
---@param annotation CodeCompanion.Annotation
---@return string
local function format_annotation(annotation)
  return fmt(
    [[<annotation file="%s" lines="%d-%d">
````%s
%s
````
%s
</annotation>]],
    annotation.path,
    annotation.start_line,
    annotation.end_line,
    annotation.filetype or "",
    annotation.code,
    annotation.comment
  )
end

---Format all pending annotations into a single message
---@param pending CodeCompanion.Annotation[]
---@return string
local function format_all(pending)
  local blocks = {}
  for _, annotation in ipairs(pending) do
    table.insert(blocks, format_annotation(annotation))
  end

  return "Here are my annotations:\n\n" .. table.concat(blocks, "\n\n")
end

---Render in the chat interaction
---@return nil
function EditorContext:chat_render()
  local pending = annotations.all()
  if #pending == 0 then
    return log:warn("No annotations found")
  end

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = format_all(pending),
  }, { _meta = { source = "editor_context", tag = tags.ANNOTATIONS }, visible = false })

  annotations.clear()
end

---Render in the CLI interaction
---@return { inline: string, block: string }|nil
function EditorContext:cli_render()
  local pending = annotations.all()
  if #pending == 0 then
    log:warn("No annotations found")
    return nil
  end

  local result = {
    inline = "my annotations",
    block = format_all(pending),
  }

  annotations.clear()

  return result
end

return EditorContext
