local code_review = require("codecompanion.interactions.code_review")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local tags = require("codecompanion.interactions.shared.tags")

local fmt = string.format

local CONSTANTS = {
  EDITOR_CONTEXT_TAG = "{code_review}",
}

---@class CodeCompanion.EditorContext.CodeReview: CodeCompanion.EditorContext
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

---Format a comment's file and line range, as `path:1` or `path:1-4`
---@param comment CodeCompanion.CodeReview.Comment
---@return string
local function format_file_loc(comment)
  if comment.start_line == comment.end_line then
    return fmt("%s:%d", comment.path, comment.start_line)
  end
  return fmt("%s:%d-%d", comment.path, comment.start_line, comment.end_line)
end

---Format a code review comment into a `<comment>` block
---@param comment CodeCompanion.CodeReview.Comment
---@return string
local function format_comment(comment)
  return fmt(
    [[<comment file="%s" lines="%d-%d">
````%s
%s
````
%s
</comment>]],
    comment.path,
    comment.start_line,
    comment.end_line,
    comment.filetype or "",
    comment.code,
    comment.comment
  )
end

---Format all pending comments into a single message
---@param comments CodeCompanion.CodeReview.Comment[]
---@return string
local function format_all(comments)
  local blocks = {}
  for _, comment in ipairs(comments) do
    table.insert(blocks, format_comment(comment))
  end

  return "Here are the comments from my code review:\n\n" .. table.concat(blocks, "\n\n")
end

---Format the comments for the user to read back in the chat buffer
---@param comments CodeCompanion.CodeReview.Comment[]
---@return string
local function format_for_buffer(comments)
  local blocks = {}
  for _, comment in ipairs(comments) do
    table.insert(blocks, fmt("%s\n%s", format_file_loc(comment), comment.comment))
  end

  return fmt("\n\n````markdown\n%s\n````", table.concat(blocks, "\n\n"))
end

---Render in the chat interaction
---@return nil
function EditorContext:chat_render()
  local comments = code_review.consume()
  if not comments then
    return log:warn("No code review comments found")
  end

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = format_all(comments),
  }, { _meta = { source = "editor_context", tag = tags.CODE_REVIEW }, visible = false })

  self.Chat:add_buf_message({
    role = config.constants.USER_ROLE,
    content = format_for_buffer(comments),
  }, { type = self.Chat.MESSAGE_TYPES.USER_MESSAGE })
end

---Replace the editor context tag in the message
---@param prefix string
---@param message string
---@return string
function EditorContext.replace(prefix, message)
  local replacement = config.interactions.shared.editor_context.code_review.opts.replacement_message

  message = message:gsub(prefix .. CONSTANTS.EDITOR_CONTEXT_TAG .. "{[^}]*}", replacement)
  message = message:gsub(prefix .. CONSTANTS.EDITOR_CONTEXT_TAG, replacement)

  return message
end

---Render in the CLI interaction
---@return { inline: string, block: string }|nil
function EditorContext:cli_render()
  local pending = code_review.consume()
  if not pending then
    log:warn("No code review comments found")
    return nil
  end

  return {
    inline = "code review comments",
    block = format_all(pending),
  }
end

return EditorContext
