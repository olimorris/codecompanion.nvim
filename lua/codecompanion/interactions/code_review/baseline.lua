local hash = require("codecompanion.utils.hash")
local log = require("codecompanion.utils.log")

local fmt = string.format

local CONSTANTS = {
  INDEX_NAME = "codecompanion-index",
  ABANDON_LOCK_AFTER = 60,
  MAX_CHANGED_LINE_LENGTH = 60, -- Longest changed line to show in a hunk's summary

  -- Use a fixed identity so snapshots work in repos with no user.name/user.email
  IDENTITY = {
    GIT_AUTHOR_NAME = "CodeCompanion",
    GIT_AUTHOR_EMAIL = "codecompanion@neovim",
    GIT_COMMITTER_NAME = "CodeCompanion",
    GIT_COMMITTER_EMAIL = "codecompanion@neovim",
  },

  -- The refs/worktree namespace is per-worktree (like HEAD)
  -- This ensures that agents in linked worktrees never share a baseline
  REF_ALIAS = "refs/worktree/codecompanion/baseline",
  REF_PREFIX = "refs/worktree/codecompanion/baselines/",
}

---@class CodeCompanion.CodeReview.Hunk
---@field id number Content hash of the hunk, stable until the change itself changes
---@field line number First changed line in the current version of the file
---@field path string Path of the changed file, relative to the repo root
---@field summary string Added/removed counts plus the first line the hunk changes, e.g. "+3 -1 local timeout = 30"

local M = {}

---Run a git command in the repo, returning the finished process
---@param root string
---@param args string[]
---@param env? table<string, string>
---@return vim.SystemCompleted|nil
local function run(root, args, env)
  local ok, result = pcall(function()
    return vim.system(vim.list_extend({ "git" }, args), { cwd = root, env = env, text = true }):wait()
  end)

  if not ok then
    return nil
  end

  return result
end

---Run a git command in the repo, returning trimmed stdout or nil on failure
---@param root string
---@param args string[]
---@param env? table<string, string>
---@return string|nil
local function git(root, args, env)
  local result = run(root, args, env)
  if not result or result.code ~= 0 then
    return nil
  end

  return vim.trim(result.stdout or "")
end

---@type table<string, string>
local git_dirs = {}

---The worktree's own git directory, which is where git keeps per-worktree state like the index
---@param root string
---@return string|nil
local function git_dir(root)
  if not git_dirs[root] then
    git_dirs[root] = git(root, { "rev-parse", "--absolute-git-dir" })
  end

  return git_dirs[root]
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

---Copy the user's index to seed ours. Git's stat cache spares us re-hashing every file
---@param root string
---@param index string
---@return nil
local function seed(root, index)
  if vim.uv.fs_stat(index) then
    return
  end

  local dir = git_dir(root)
  if not dir then
    return
  end

  vim.uv.fs_copyfile(vim.fs.joinpath(dir, "index"), index)
end

---Did the git command abort?
---@param result vim.SystemCompleted|nil
---@return boolean
local function aborted(result)
  -- NOTE: Git names the paths it skipped with an "error" message and carries
  -- on. However, any aborts receive a "fatal" message
  return result == nil or (result.stderr or ""):find("fatal:", 1, true) ~= nil
end

---Add the worktree to an index and write it out as a tree object
---@param root string
---@param index string
---@return string|nil tree
local function write_tree(root, index)
  local env = { GIT_INDEX_FILE = index }

  -- Skip the paths that git can't index
  if aborted(run(root, { "add", "--all", "--ignore-errors", "." }, env)) then
    return nil
  end

  return git(root, { "write-tree" }, env)
end

---Throw our index away so the next write rebuilds it
---@param index string
---@return nil
local function discard(index)
  local lock = vim.uv.fs_stat(index .. ".lock")

  -- A live snapshot holds its lock for milliseconds, so anything this old was abandoned.
  -- Taking one that's still held would let two writers rename over each other's index
  if lock and os.time() - lock.mtime.sec > CONSTANTS.ABANDON_LOCK_AFTER then
    vim.uv.fs_unlink(index .. ".lock")
  end

  vim.uv.fs_unlink(index)
end

---Write the worktree (including untracked files) to a git tree object
---@param root string
---@return string|nil tree
local function write_worktree(root)
  local dir = git_dir(root)
  if not dir then
    return nil
  end

  local index = vim.fs.joinpath(dir, CONSTANTS.INDEX_NAME)
  seed(root, index)

  local tree = write_tree(root, index)
  if tree then
    return tree
  end

  -- Our index is only ever a cache, so whatever is wrong with it is fixed by
  -- starting again. A tree from a stale index would silently drop this
  -- round's changes, so it's never reused
  log:info("[Code Review] Rebuilding `%s`", index)
  discard(index)
  seed(root, index)

  return write_tree(root, index)
end

---Summarise the first changed line in a hunk so it can be displayed to the user
---@param body string[]
---@return string|nil
local function changed_line(body)
  local removed
  for _, line in ipairs(body) do
    local text = vim.trim(line:sub(2))
    if text ~= "" then
      if line:sub(1, 1) == "+" then
        return vim.fn.strcharpart(text, 0, CONSTANTS.MAX_CHANGED_LINE_LENGTH)
      end
      removed = removed or vim.fn.strcharpart(text, 0, CONSTANTS.MAX_CHANGED_LINE_LENGTH)
    end
  end

  -- Only a pure deletion has nothing added to show
  return removed
end

---Parse unified diff output into one entry per hunk
---@param output string
---@return CodeCompanion.CodeReview.Hunk[]
local function parse_hunks(output)
  local hunks = {}
  local old_path, path, body

  local function finish()
    local hunk = hunks[#hunks]
    if not hunk or hunk.id then
      return
    end

    hunk.id = hash.hash(hunk.path .. "\n" .. table.concat(body or {}, "\n"))

    local changed = changed_line(body or {})
    if changed then
      hunk.summary = hunk.summary .. " " .. changed
    end
  end

  for line in output:gmatch("[^\n]+") do
    local old_count, new_start, new_count = line:match("^@@ %-%d+,?(%d*) %+(%d+),?(%d*) @@")
    if line:match("^diff %-%-git ") then
      finish()
      old_path, path, body = nil, nil, nil
    -- NOTE: A removed line can read `--- foo`, so only take these as headers
    -- before the file's first hunk has opened a body for them to fall into
    elseif not body and line:match("^%-%-%- ") then
      old_path = line:match('^%-%-%- "?a/(.-)"?$')
    elseif not body and line:match("^%+%+%+ ") then
      -- Deleted files diff to /dev/null, so fall back to the old side's path
      path = line:match('^%+%+%+ "?b/(.-)"?$') or old_path
    elseif new_start and path then
      finish()
      body = {}
      table.insert(hunks, {
        path = path,
        -- Pure deletions report the line before the removal, which can be 0
        line = math.max(tonumber(new_start) or 1, 1),
        summary = fmt("+%s -%s", new_count ~= "" and new_count or "1", old_count ~= "" and old_count or "1"),
      })
    elseif body and line:match("^[+%-]") then
      table.insert(body, line)
    end
  end
  finish()

  return hunks
end

---Get the git root for the current working directory
---@return string|nil
function M.get_root()
  if vim.fn.executable("git") == 0 then
    return nil
  end

  return vim.fs.root(vim.uv.cwd() or 0, ".git")
end

---The root that a review's state is stored against
---@return string
function M.storage_root()
  return M.get_root() or vim.fs.normalize(vim.uv.cwd() or "")
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

---The stable ref that always follows the current baseline, for gitsigns/diffview
---@return string
function M.alias()
  return CONSTANTS.REF_ALIAS
end

---Show a file's contents at the baseline
---@param root string
---@param path string A path relative to the root
---@return string[]
function M.show(root, path)
  local ok, result = pcall(function()
    return vim.system({ "git", "show", ref_for(root) .. ":" .. path }, { cwd = root, text = true }):wait()
  end)

  if not ok or result.code ~= 0 then
    return {}
  end

  local lines = vim.split(result.stdout or "", "\n")
  if lines[#lines] == "" then
    table.remove(lines)
  end

  return lines
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

---Snapshot the worktree to the baseline ref, returning the new commit sha
---@param root string
---@return string|nil
function M.snapshot(root)
  local ref = ref_for(root)
  local tree = write_worktree(root)
  local commit = tree and git(root, { "commit-tree", tree, "-m", "CodeCompanion review baseline" }, CONSTANTS.IDENTITY)
  local updated = commit and git(root, { "update-ref", ref, commit })

  if not updated then
    log:info("[Code Review] Could not snapshot the review baseline")
    return nil
  end

  sync_alias(root, ref)
  return commit
end

---Diff the current worktree against the baseline, one entry per hunk
---@param root string
---@param paths? string[] Limit the diff to these paths, relative to the root
---@return CodeCompanion.CodeReview.Hunk[]|nil hunks Nil when the worktree couldn't be read
function M.diff(root, paths)
  local worktree = write_worktree(root)
  if not worktree then
    return nil
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
