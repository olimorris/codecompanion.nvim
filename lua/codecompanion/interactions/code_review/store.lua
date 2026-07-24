local baseline = require("codecompanion.interactions.code_review.baseline")
local config = require("codecompanion.config")
local files = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

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
local function remove(path)
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
    "## %s:%d-%d\n\n````%s\n%s\n````\n\n%s",
    comment.path,
    comment.start_line,
    comment.end_line,
    comment.filetype or "",
    comment.code,
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
---@param markdown string
---@return CodeCompanion.CodeReview.Comment[]
local function parse(markdown)
  local comments = {}
  local comment, prose, code
  local in_fence = false

  for _, line in ipairs(vim.split(markdown, "\n", { plain = true })) do
    local path, start_line, end_line = line:match("^## (.+):(%d+)%-(%d+)%s*$")
    if path and not in_fence then
      finish(comments, comment, prose or {})
      comment = { path = path, start_line = tonumber(start_line), end_line = tonumber(end_line) }
      prose, code = {}, nil
    elseif comment then
      local fence_filetype = line:match("^````(%S*)%s*$")
      if not in_fence and not comment.code and fence_filetype then
        in_fence = true
        comment.filetype = fence_filetype ~= "" and fence_filetype or nil
        code = {}
      elseif in_fence and line:match("^````%s*$") then
        in_fence = false
        comment.code = table.concat(code, "\n")
      elseif in_fence then
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

---Return all pending comments for a repo
---@param root string
---@return CodeCompanion.CodeReview.Comment[]
function M.comments(root)
  local path = M.comments_path(root)
  if not files.exists(path) then
    return {}
  end

  return parse(files.read(path))
end

---Append a comment to the store
---@param root string
---@param comment CodeCompanion.CodeReview.Comment
---@return nil
function M.add_comment(root, comment)
  local path = M.comments_path(root)
  local existing = files.exists(path) and files.read(path) or ""
  local separator = existing ~= "" and "\n" or ""

  files.write_to_path(path, existing .. separator .. format(comment) .. "\n")
end

---Remove all pending comments for a repo
---@param root string
---@return nil
function M.clear_comments(root)
  remove(M.comments_path(root))
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
  local success, error_message = files.rename(M.comments_path(root), M.review_path(root))
  if not success then
    log:error("[Code Review] Could not write the file: `%s`", error_message)
    return nil
  end

  return M.review_path(root)
end

local edited_files_path = branch_file("edited_files.txt")

---Return the files an agent has edited since the baseline, relative to the root
---@param root string
---@return string[]
function M.edited(root)
  return read_lines(edited_files_path(root))
end

---Record a file an agent has edited, ignoring paths outside the repo
---@param root string
---@param filepath string An absolute path
---@return nil
function M.track(root, filepath)
  local relative = vim.fs.relpath(root, filepath)
  if not relative then
    return
  end

  local edited = M.edited(root)
  if vim.list_contains(edited, relative) then
    return
  end

  table.insert(edited, relative)
  files.write_to_path(edited_files_path(root), table.concat(edited, "\n") .. "\n")
end

---Forget the edited files for a repo
---@param root string
---@return nil
function M.clear_edited(root)
  remove(edited_files_path(root))
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

---Forget the accepted hunks for a repo
---@param root string
---@return nil
function M.clear_accepted(root)
  remove(accepted_path(root))
end

local ignored_files_path = branch_file("ignored_files.txt")

---Return the files the user has ignored, as a set of root-relative paths
---@param root string
---@return table<string, boolean>
function M.ignored(root)
  return read_set(ignored_files_path(root))
end

---Record a file the user has ignored
---@param root string
---@param path string A path relative to the root
---@return nil
function M.ignore(root, path)
  append(ignored_files_path(root), path)
end

---Forget the ignored files for a repo
---@param root string
---@return nil
function M.clear_ignored(root)
  remove(ignored_files_path(root))
end

return M
