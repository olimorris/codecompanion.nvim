local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local fmt = string.format

---@class CodeCompanion.EditorContext.Diff: CodeCompanion.EditorContext
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
function EditorContext:apply()
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

return EditorContext
