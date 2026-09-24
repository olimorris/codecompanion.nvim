local baseline = require("codecompanion.interactions.code_review.baseline")
local config = require("codecompanion.config")
local files = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")
local markdown = require("codecompanion.utils.markdown")

local fmt = string.format

---@class CodeCompanion.CodeReview.Comment
---@field comment string
---@field code string
---@field filetype? string
---@field path string
---@field start_line number
---@field end_line number

local M = {}

---@param root string
---@return string
local function get_dir(root)
  return vim.fs.joinpath(config.interactions.code_review.opts.storage_dir, files.flatten_path(root))
end

---@param root string
---@return string
local function get_branch_dir(root)
  local branch = baseline.get_branch(root)
  if not branch then
    -- Detached HEAD, or no git at all; state lives at the repo level
    return get_dir(root)
  end

  return vim.fs.joinpath(get_dir(root), files.flatten_path(branch))
end

---@param name string The file's name within the branch directory
---@return fun(root: string): string
local function branch_file(name)
  return function(root)
    return vim.fs.joinpath(get_branch_dir(root), name)
  end
end

---@param path string
---@return nil
local function delete(path)
  if files.exists(path) then
    files.delete(path)
  end
end

---@param path string
---@return string[]
local function read_lines(path)
  if not files.exists(path) then
    return {}
  end
  return vim.tbl_filter(function(line)
    return line ~= ""
  end, files.read_lines(path))
end

---Read a file of lines into a set
---@param path string
---@return table<string, boolean>
local function read_set(path)
  local set = {}
  for _, line in ipairs(read_lines(path)) do
    set[line] = true
  end
  return set
end

---Append a line to a file, skipped when it's already present
---@param path string
---@param value string
---@return nil
local function append(path, value)
  if read_set(path)[value] then
    return
  end
  local existing = files.exists(path) and files.read(path) or ""
  files.write_to_path(path, existing .. value .. "\n")
end

---Format a comment as a markdown section
---@param comment CodeCompanion.CodeReview.Comment
---@return string
local function format(comment)
  return fmt(
    "## %s:%d-%d\n\n%s\n\n%s",
    comment.path,
    comment.start_line,
    comment.end_line,
    markdown.form_codeblock(comment.code, { ft = comment.filetype }),
    comment.comment
  )
end

---Close off a comment section being parsed, keeping it only if it has any text
---@param comments CodeCompanion.CodeReview.Comment[]
---@param comment? table
---@param prose string[]
---@return nil
local function finish(comments, comment, prose)
  if not comment then
    return
  end
  comment.code = comment.code or ""
  comment.comment = vim.trim(table.concat(prose, "\n"))
  if comment.comment == "" then
    return log:warn("[Code Review] Skipping a comment with no text (%s:%d)", comment.path, comment.start_line)
  end
  table.insert(comments, comment)
end

---Parse the markdown comments file back into comments
---@param contents string
---@return CodeCompanion.CodeReview.Comment[]
local function parse(contents)
  local comments = {}
  local comment, prose, code
  local open_backticks

  for _, line in ipairs(vim.split(contents, "\n", { plain = true })) do
    local path, start_line, end_line = line:match("^## (.+):(%d+)%-(%d+)%s*$")
    if path and not open_backticks then
      finish(comments, comment, prose or {})
      comment = { path = path, start_line = tonumber(start_line), end_line = tonumber(end_line) }
      prose, code = {}, nil
    elseif comment then
      local backticks, ft = line:match("^(````+)(%S*)%s*$")
      if not open_backticks and not comment.code and backticks then
        open_backticks = backticks
        comment.filetype = ft ~= "" and ft or nil
        code = {}
      elseif open_backticks and line:match("^" .. open_backticks .. "%s*$") then
        open_backticks = nil
        comment.code = table.concat(code, "\n")
      elseif open_backticks then
        table.insert(code, line)
      else
        table.insert(prose, line)
      end
    end
  end
  finish(comments, comment, prose or {})

  return comments
end

---The path of the comments file for a repo
---@param root string
---@return string
function M.comments_path(root)
  return vim.fs.joinpath(get_branch_dir(root), "comments.md")
end

---@param path string
---@return CodeCompanion.CodeReview.Comment[]
local function read_blocks(path)
  if not files.exists(path) then
    return {}
  end
  return parse(files.read(path))
end

---Write comments as markdown sections, or delete the file when there are none
---@param path string
---@param comments CodeCompanion.CodeReview.Comment[]
---@return nil
local function write_blocks(path, comments)
  if #comments == 0 then
    return delete(path)
  end

  local blocks = {}
  for _, comment in ipairs(comments) do
    table.insert(blocks, format(comment))
  end

  files.write_to_path(path, table.concat(blocks, "\n") .. "\n")
end

---Return all pending comments for a repo
---@param root string
---@return CodeCompanion.CodeReview.Comment[]
function M.comments(root)
  return read_blocks(M.comments_path(root))
end

---@param path string
---@param comment CodeCompanion.CodeReview.Comment
---@return nil
local function append_block(path, comment)
  local existing = files.exists(path) and files.read(path) or ""
  local separator = existing ~= "" and "\n" or ""

  files.write_to_path(path, existing .. separator .. format(comment) .. "\n")
end

---Append a comment to the store
---@param root string
---@param comment CodeCompanion.CodeReview.Comment
---@return nil
function M.add_comment(root, comment)
  append_block(M.comments_path(root), comment)
end

---Write the pending comments to disk, or, delete the file if there are none
---@param root string
---@param comments CodeCompanion.CodeReview.Comment[]
---@return nil
function M.write_comments(root, comments)
  write_blocks(M.comments_path(root), comments)
end

---Delete all pending comments for a repo
---@param root string
---@return nil
function M.clear_comments(root)
  delete(M.comments_path(root))
end

---The path of the last submitted review for a repo
---@param root string
---@return string
function M.review_path(root)
  -- Repo-level, not per-branch, so the path referenced in e.g. a CLAUDE.md stays static
  return vim.fs.joinpath(get_dir(root), "review.md")
end

---Move the pending comments to the submitted review file, returning its path
---@param root string
---@return string|nil
function M.submit(root)
  local ok, error = files.rename(M.comments_path(root), M.review_path(root))
  if not ok then
    log:error("[Code Review] Could not write the file: `%s`", error)
    return nil
  end

  return M.review_path(root)
end

local sent_path = branch_file("sent.md")

---The comments sent with the last review, kept so the agent's response can be read against them
---@param root string
---@return CodeCompanion.CodeReview.Comment[]
function M.sent(root)
  return read_blocks(sent_path(root))
end

---@param root string
---@param comments CodeCompanion.CodeReview.Comment[]
---@return nil
function M.write_sent(root, comments)
  write_blocks(sent_path(root), comments)
end

---@param root string
---@return nil
function M.clear_sent(root)
  delete(sent_path(root))
end

local explanations_path = branch_file("explanations.md")

---The file an agent is asked to write its explanations to, one `## path:first-last` section per change
---@param root string
---@return string
function M.explanations_path(root)
  return explanations_path(root)
end

---@param root string
---@return CodeCompanion.CodeReview.Comment[]
function M.explanations(root)
  return read_blocks(explanations_path(root))
end

---Record an explanation written on the agent's behalf, when a fresh model answered instead
---@param root string
---@param explanation CodeCompanion.CodeReview.Comment
---@return nil
function M.add_explanation(root, explanation)
  append_block(explanations_path(root), explanation)
end

---@param root string
---@return nil
function M.clear_explanations(root)
  delete(explanations_path(root))
end

local channel_path = branch_file("channel.json")

---Remember which chat or CLI buffer is driving the round, so its agent can be asked about the changes
---@param root string
---@param channel CodeCompanion.CodeReview.Channel
---@return nil
function M.set_round_channel(root, channel)
  files.write_to_path(channel_path(root), vim.json.encode(channel))
end

---@param root string
---@return CodeCompanion.CodeReview.Channel|nil
function M.round_channel(root)
  local path = channel_path(root)
  if not files.exists(path) then
    return nil
  end

  local ok, channel = pcall(vim.json.decode, files.read(path))
  return ok and channel or nil
end

local round_path = branch_file("round")

---Mark a round of agent work as begun, so the baseline holds until it's reviewed
---@param root string
---@return nil
function M.begin_round(root)
  files.write_to_path(round_path(root), "")
end

---Has a round of agent work begun since the baseline was last advanced?
---@param root string
---@return boolean
function M.round_open(root)
  return files.exists(round_path(root))
end

---Close the round, so the next submission re-baselines
---@param root string
---@return nil
function M.clear_round(root)
  delete(round_path(root))
  delete(channel_path(root))
end

local accepted_path = branch_file("accepted.txt")

---Return the ids of the hunks the user has accepted, as a set
---@param root string
---@return table<string, boolean>
function M.accepted(root)
  return read_set(accepted_path(root))
end

---Record a hunk the user has accepted
---@param root string
---@param id number
---@return nil
function M.accept(root, id)
  append(accepted_path(root), tostring(id))
end

---Take a hunk back out of the accepted set
---@param root string
---@param id number|string
---@return nil
function M.unaccept(root, id)
  local path = accepted_path(root)
  local kept = vim.tbl_filter(function(line)
    return line ~= tostring(id)
  end, read_lines(path))

  if #kept == 0 then
    return delete(path)
  end

  files.write_to_path(path, table.concat(kept, "\n") .. "\n")
end

---Forget the accepted hunks for a repo
---@param root string
---@return nil
function M.clear_accepted(root)
  delete(accepted_path(root))
end

return M
