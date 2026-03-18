local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local fmt = string.format

---@class CodeCompanion.EditorContext.Diff: CodeCompanion.EditorContext
local EditorContext = {}

---@param args CodeCompanion.EditorContextArgs
function EditorContext.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    buffer_context = args.buffer_context or (args.Chat and args.Chat.buffer_context),
    config = args.config,
    params = args.params,
    target = args.target,
  }, { __index = EditorContext })

  return self
end

---Run a git command and return stdout
---@param cmd string[]
---@return string|nil
local function git(cmd)
  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  return result.stdout
end

---Add the current git diff to the chat
---@return nil
function EditorContext:chat_render()
  local is_git = git({ "git", "rev-parse", "--is-inside-work-tree" })
  if not is_git then
    return log:warn("Not inside a git repository")
  end

  local unstaged = git({ "git", "diff", "--no-ext-diff" }) or ""
  local staged = git({ "git", "diff", "--no-ext-diff", "--cached" }) or ""

  if unstaged == "" and staged == "" then
    return log:warn("No git changes found")
  end

  local content = {}
  if unstaged ~= "" then
    table.insert(content, fmt("Unstaged changes:\n\n````diff\n%s````", unstaged))
  end
  if staged ~= "" then
    table.insert(content, fmt("Staged changes:\n\n````diff\n%s````", staged))
  end

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = table.concat(content, "\n\n"),
  }, { _meta = { source = "editor_context", tag = "diff" }, visible = false })
end

---Return inline label and context block for the CLI interaction
---@return { inline: string, block: string }|nil
function EditorContext:cli_render()
  local is_git = git({ "git", "rev-parse", "--is-inside-work-tree" })
  if not is_git then
    log:warn("Not inside a git repository")
    return nil
  end

  local unstaged = git({ "git", "diff", "--no-ext-diff" }) or ""
  local staged = git({ "git", "diff", "--no-ext-diff", "--cached" }) or ""

  if unstaged == "" and staged == "" then
    log:warn("No git changes found")
    return nil
  end

  local content = {}
  if unstaged ~= "" then
    table.insert(
      content,
      fmt(
        [[- Unstaged changes:
````diff
%s
````]],
        unstaged
      )
    )
  end
  if staged ~= "" then
    table.insert(
      content,
      fmt(
        [[- Staged changes:
````diff
%s
````]],
        staged
      )
    )
  end

  return {
    inline = "the git diff",
    block = table.concat(content, "\n\n"),
  }
end

return EditorContext
