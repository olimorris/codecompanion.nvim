local hash = require("codecompanion.utils.hash")
local log = require("codecompanion.utils.log")

local fmt = string.format

local CONSTANTS = {
  -- The refs/worktree namespace is per-worktree (like HEAD), so agents in linked worktrees never share a baseline
  REF_ALIAS = "refs/worktree/codecompanion/baseline",
  REF_PREFIX = "refs/worktree/codecompanion/baselines/",

  -- Use a fixed identity so snapshots work in repos with no user.name/user.email
  IDENT = {
    GIT_AUTHOR_NAME = "CodeCompanion",
    GIT_AUTHOR_EMAIL = "codecompanion@neovim",
    GIT_COMMITTER_NAME = "CodeCompanion",
    GIT_COMMITTER_EMAIL = "codecompanion@neovim",
  },
}

---@class CodeCompanion.CodeReview.Hunk
---@field id number Content hash of the hunk, stable until the change itself changes
---@field line number First changed line in the current version of the file
---@field path string Path of the changed file, relative to the repo root
---@field summary string Added/removed counts plus any hunk context, e.g. "+3 -1 local function foo()"

local M = {}

---Run a git command in the repo, returning trimmed stdout or nil on failure
---@param root string
---@param args string[]
---@param env? table<string, string>
---@return string|nil
local function git(root, args, env)
  local ok, result = pcall(function()
    return vim.system(vim.list_extend({ "git" }, args), { cwd = root, env = env, text = true }):wait()
  end)

  if not ok or result.code ~= 0 then
    return nil
  end

  return vim.trim(result.stdout or "")
end

---Get the git root for the current working directory
---@return string|nil
function M.get_root()
  if vim.fn.executable("git") == 0 then
    return nil
  end

  return vim.fs.root(vim.uv.cwd() or 0, ".git")
end

---Get the checked-out branch for a repo, if HEAD isn't detached
---@param root string
---@return string|nil
function M.get_branch(root)
  local branch = git(root, { "branch", "--show-current" })
  if not branch or branch == "" then
    return nil
  end

  return branch
end

---The ref for the checked-out branch
---@param root string
---@return string
local function ref_for(root)
  local branch = M.get_branch(root)
  if not branch then
    return CONSTANTS.REF_ALIAS
  end

  return CONSTANTS.REF_PREFIX .. branch
end

---Point the stable alias ref at the baseline in use, for gitsigns/diffview
---@param root string
---@param ref string
---@return nil
local function sync_alias(root, ref)
  if ref ~= CONSTANTS.REF_ALIAS then
    git(root, { "update-ref", CONSTANTS.REF_ALIAS, ref })
  end
end

---Return the baseline commit sha, if one exists
---@param root string
---@return string|nil
function M.get(root)
  local sha = git(root, { "rev-parse", "--quiet", "--verify", ref_for(root) })
  if not sha or sha == "" then
    return nil
  end

  return sha
end

---Write the worktree (including untracked files) to a git tree object
---@param root string
---@return string|nil tree
local function write_worktree(root)
  -- Use a temp index to leave the real index untouched
  local index = vim.fn.tempname()
  local env = { GIT_INDEX_FILE = index }

  local staged = git(root, { "add", "--all", "." }, env)
  local tree = staged and git(root, { "write-tree" }, env)

  vim.uv.fs_unlink(index)
  return tree
end

---Snapshot the worktree to the baseline ref, returning the new commit sha
---@param root string
---@return string|nil
function M.snapshot(root)
  local ref = ref_for(root)
  local tree = write_worktree(root)
  local commit = tree and git(root, { "commit-tree", tree, "-m", "CodeCompanion review baseline" }, CONSTANTS.IDENT)
  local updated = commit and git(root, { "update-ref", ref, commit })

  if not updated then
    log:error("[Code Review] Could not snapshot the review baseline")
    return nil
  end

  sync_alias(root, ref)
  return commit
end

---Parse unified diff output into one entry per hunk
---@param output string
---@return CodeCompanion.CodeReview.Hunk[]
local function parse_hunks(output)
  local hunks = {}
  local old_path, path, body

  local function finish()
    local hunk = hunks[#hunks]
    if hunk and not hunk.id then
      hunk.id = hash.hash(hunk.path .. "\n" .. table.concat(body or {}, "\n"))
    end
  end

  for line in output:gmatch("[^\n]+") do
    local old_count, new_start, new_count = line:match("^@@ %-%d+,?(%d*) %+(%d+),?(%d*) @@")
    if line:match("^%-%-%- ") then
      finish()
      old_path = line:match('^%-%-%- "?a/(.-)"?$')
    elseif line:match("^%+%+%+ ") then
      -- Deleted files diff to /dev/null, so fall back to the old side's path
      path = line:match('^%+%+%+ "?b/(.-)"?$') or old_path
    elseif new_start and path then
      finish()
      body = {}
      local context = line:match("^@@ .- @@ (.*)$")
      local summary = fmt("+%s -%s", new_count ~= "" and new_count or "1", old_count ~= "" and old_count or "1")
      if context and context ~= "" then
        summary = summary .. " " .. context
      end
      table.insert(hunks, {
        path = path,
        -- Pure deletions report the line before the removal, which can be 0
        line = math.max(tonumber(new_start) or 1, 1),
        summary = summary,
      })
    elseif body and line:match("^[+%-]") then
      table.insert(body, line)
    end
  end
  finish()

  return hunks
end

---Diff the current worktree against the baseline, one entry per hunk
---Both sides are worktree snapshots, so untracked files and the state of the
---user's index never affect the result
---@param root string
---@param paths? string[] Limit the diff to these paths, relative to the root
---@return CodeCompanion.CodeReview.Hunk[]
function M.diff(root, paths)
  local worktree = write_worktree(root)
  if not worktree then
    return {}
  end

  local ref = ref_for(root)
  sync_alias(root, ref)

  local args = { "diff", "--no-color", "--no-ext-diff", "--unified=0", ref, worktree, "--" }
  if paths then
    vim.list_extend(args, paths)
  end

  local output = git(root, args)
  if not output or output == "" then
    return {}
  end
  return parse_hunks(output)
end

return M
