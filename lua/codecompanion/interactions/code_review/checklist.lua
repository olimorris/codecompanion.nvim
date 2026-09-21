local baseline = require("codecompanion.interactions.code_review.baseline")
local diff = require("codecompanion.diff")
local files = require("codecompanion.utils.files")
local store = require("codecompanion.interactions.code_review.store")

local api = vim.api
local fmt = string.format

local M = {}

---@class CodeCompanion.CodeReview.Entry
---@field hunk? number Index into the file's diff hunks
---@field ids? string[] The baseline hunks this one covers, which is what accepting records
---@field kind "file"|"hunk"
---@field path string
---@field spans? { added: number[], removed: number[] } Byte ranges of the `+N` and `-N` counts

---Throw away the scratch buffers holding each file's diff
---@param diffs table<string, CC.Diff>
---@return nil
function M.discard(diffs)
  for _, file_diff in pairs(diffs) do
    pcall(api.nvim_buf_delete, file_diff.bufnr, { force = true })
  end
end

---A changed file's name with the directory holding it, so two `init.lua` rows can be told apart
---@param path string
---@return string
local function shorten_path(path)
  local parent = vim.fn.fnamemodify(path, ":h:t")
  if parent == "" or parent == "." then
    return path
  end

  return vim.fs.joinpath(parent, vim.fn.fnamemodify(path, ":t"))
end

---Read a file, dropping the empty element `files.read_lines` leaves for the newline at end of file
---@param root string
---@param path string
---@return string[]
function M.read_file_lines(root, path)
  local lines = files.read_lines(vim.fs.joinpath(root, path)) or {}

  -- `baseline.show` strips it too, and feeding both sides in unmatched makes every file look changed
  if lines[#lines] == "" then
    table.remove(lines)
  end

  return lines
end

---@param opts { root: string, path: string, from: string[], to: string[] }
---@return CC.Diff
local function create_diff(opts)
  return diff.create({
    bufnr = api.nvim_create_buf(false, true),
    from_lines = opts.from,
    to_lines = opts.to,
    ft = vim.filetype.match({ filename = vim.fs.joinpath(opts.root, opts.path) }),
  })
end

---The ids of the baseline hunks that fall inside a displayed hunk
---@param opts { git_hunks: CodeCompanion.CodeReview.Hunk[], hunk: CodeCompanion.diff.Hunk }
---@return string[]
local function get_baseline_ids(opts)
  local hunk = opts.hunk

  -- A hunk that only deletes covers the single line it sits after
  local first = math.max(hunk.to_start, 1)
  local last = math.max(first, hunk.to_start + hunk.to_count - 1)

  local ids = {}
  for _, git_hunk in ipairs(opts.git_hunks) do
    if git_hunk.line >= first and git_hunk.line <= last then
      table.insert(ids, tostring(git_hunk.id))
    end
  end

  return ids
end

---Rewrite the baseline side so the accepted hunks read as context rather than as edits
---@param opts { from: string[], to: string[], hunks: CodeCompanion.diff.Hunk[] } `hunks` are the accepted ones
---@return string[]
local function fold_accepted_into_baseline(opts)
  local folded = opts.from

  -- Bottom-up, or an earlier splice shifts the line numbers of the ones below it
  for index = #opts.hunks, 1, -1 do
    local hunk = opts.hunks[index]
    local at = hunk.kind == "add" and hunk.from_start + 1 or hunk.from_start

    local spliced = vim.list_slice(folded, 1, at - 1)
    vim.list_extend(spliced, vim.list_slice(opts.to, hunk.to_start, hunk.to_start + hunk.to_count - 1))
    vim.list_extend(spliced, vim.list_slice(folded, at + hunk.from_count))
    folded = spliced
  end

  return folded
end

---Diff a file against the baseline, with anything already accepted folded into the baseline side
---@param opts { root: string, path: string, accepted: table<string, boolean>, git_hunks: CodeCompanion.CodeReview.Hunk[] }
---@return CC.Diff
local function build_diff(opts)
  local from = baseline.show(opts.root, opts.path)
  local to = M.read_file_lines(opts.root, opts.path)
  local file_diff = create_diff({ root = opts.root, path = opts.path, from = from, to = to })

  local settled = {}
  for _, hunk in ipairs(file_diff.hunks) do
    local ids = get_baseline_ids({ git_hunks = opts.git_hunks, hunk = hunk })
    local all_accepted = #ids > 0 and vim.iter(ids):all(function(id)
      return opts.accepted[id]
    end)

    if all_accepted then
      table.insert(settled, hunk)
    end
  end

  if #settled == 0 then
    return file_diff
  end

  M.discard({ file_diff })
  return create_diff({
    root = opts.root,
    path = opts.path,
    from = fold_accepted_into_baseline({ from = from, to = to, hunks = settled }),
    to = to,
  })
end

---The checklist row for a hunk, with the byte ranges of its two counts for highlighting
---@param opts { file_diff: CC.Diff, hunk: CodeCompanion.diff.Hunk }
---@return { text: string, spans: { added: number[], removed: number[] } }
local function summarise(opts)
  local file_diff, hunk = opts.file_diff, opts.hunk
  local added = fmt("+%d", hunk.to_count)
  local removed = fmt("-%d", hunk.from_count)
  local changed = hunk.to_count > 0 and file_diff.to.lines[hunk.to_start] or file_diff.from.lines[hunk.from_start]

  local added_start = 2
  local removed_start = added_start + #added + 1

  return {
    text = fmt("  %s %s  %s", added, removed, vim.trim(changed or "")),
    spans = {
      added = { added_start, added_start + #added },
      removed = { removed_start, removed_start + #removed },
    },
  }
end

---The baseline hunks still awaiting review, grouped by the file they belong to
---@param root string
---@return string[] paths
---@return table<string, CodeCompanion.CodeReview.Hunk[]> by_path
local function get_pending_hunks(root)
  local paths, by_path = {}, {}

  for _, git_hunk in ipairs(baseline.diff(root) or {}) do
    if not by_path[git_hunk.path] then
      by_path[git_hunk.path] = {}
      table.insert(paths, git_hunk.path)
    end
    table.insert(by_path[git_hunk.path], git_hunk)
  end

  return paths, by_path
end

---Build the checklist rows, the entry each row selects and the diff behind each file
---@param opts { root: string }
---@return { entries: CodeCompanion.CodeReview.Entry[], lines: string[], diffs: table<string, CC.Diff> }
function M.build(opts)
  local root = opts.root
  local accepted = store.accepted(root)
  local changed, by_path = get_pending_hunks(root)

  local paths, diffs = {}, {}
  for _, path in ipairs(changed) do
    local file_diff = build_diff({ root = root, path = path, accepted = accepted, git_hunks = by_path[path] })

    if #file_diff.hunks > 0 then
      diffs[path] = file_diff
      table.insert(paths, path)
    else
      M.discard({ file_diff })
    end
  end

  local entries, lines = {}, {}

  for _, path in ipairs(paths) do
    table.insert(entries, { kind = "file", path = path })
    table.insert(lines, shorten_path(path))

    for index, hunk in ipairs(diffs[path].hunks) do
      local summary = summarise({ file_diff = diffs[path], hunk = hunk })
      table.insert(entries, {
        kind = "hunk",
        path = path,
        hunk = index,
        ids = get_baseline_ids({ git_hunks = by_path[path], hunk = hunk }),
        spans = summary.spans,
      })
      table.insert(lines, summary.text)
    end
  end

  return { entries = entries, lines = lines, diffs = diffs }
end

return M
