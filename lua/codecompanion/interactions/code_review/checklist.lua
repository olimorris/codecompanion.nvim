local baseline = require("codecompanion.interactions.code_review.baseline")
local buffers = require("codecompanion.utils.buffers")
local config = require("codecompanion.config")
local diff = require("codecompanion.diff")
local files = require("codecompanion.utils.files")
local store = require("codecompanion.interactions.code_review.store")

local api = vim.api
local fmt = string.format

-- The gap a default `git diff` fuses into one hunk: twice its three lines of context
local GROUP_GAP = 6

local M = {}

---@class CodeCompanion.CodeReview.Entry
---@field hunks? number[] Indexes into the file's diff hunks, neighbours grouped into one row
---@field ids? string[] The baseline hunks this one covers, which is what accepting records
---@field kind "header"|"file"|"hunk"
---@field path? string Absent on the header row
---@field sent? string[] Comments sent last round against these lines, so the response can be read against the ask
---@field explanation? string What the agent, or a model, said this change does
---@field spans? table<string, number[]> Byte ranges to highlight, keyed by what they show: `path`, `added`, `removed`, `errors`, `warnings`

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

---Does the user's config say this file never needs reviewing?
---@param path string
---@return boolean
local function is_auto_accepted(path)
  for _, pattern in ipairs(config.interactions.code_review.opts.auto_accept or {}) do
    if vim.glob.to_lpeg(pattern):match(path) then
      return true
    end
  end

  return false
end

---Error and warning counts for a file, which are only known while it is loaded in a buffer
---@param root string
---@param path string
---@return { errors: number, warnings: number }
local function count_diagnostics(root, path)
  local bufnr = buffers.get_bufnr_from_path(vim.fs.joinpath(root, path))
  if not bufnr or not api.nvim_buf_is_loaded(bufnr) then
    return { errors = 0, warnings = 0 }
  end

  local counts = vim.diagnostic.count(bufnr)
  return {
    errors = counts[vim.diagnostic.severity.ERROR] or 0,
    warnings = counts[vim.diagnostic.severity.WARN] or 0,
  }
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

---The working lines a hunk touches; a hunk that only deletes covers the single line it sits after
---@param hunk CodeCompanion.diff.Hunk
---@return number first
---@return number last
local function working_span(hunk)
  local first = math.max(hunk.to_start, 1)
  return first, math.max(first, hunk.to_start + hunk.to_count - 1)
end

---The ids of the baseline hunks whose working lines overlap a displayed hunk's
---@param opts { git_hunks: CodeCompanion.CodeReview.Hunk[], hunk: CodeCompanion.diff.Hunk }
---@return string[]
local function get_baseline_ids(opts)
  local first, last = working_span(opts.hunk)

  -- Overlap rather than first line: `linematch` can split what git reports as one hunk into two
  local ids = {}
  for _, git_hunk in ipairs(opts.git_hunks) do
    local git_last = math.max(git_hunk.line, git_hunk.line + git_hunk.added - 1)
    if git_hunk.line <= last and git_last >= first then
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

---Parse the working side of a file, when Neovim has a parser for its language
---@param file_diff CC.Diff
---@return { root: TSNode, source: string }|nil
local function parse_working_file(file_diff)
  local lang = file_diff.ft and vim.treesitter.language.get_lang(file_diff.ft)
  if not lang then
    return nil
  end

  local source = table.concat(file_diff.to.lines, "\n")
  local ok, parser = pcall(vim.treesitter.get_string_parser, source, lang)
  if not ok then
    return nil
  end

  return { root = parser:parse()[1]:root(), source = source }
end

---The function, method or class node wrapped around a span of working lines
---@param opts { root: TSNode, lines: string[], first: number, last: number }
---@return TSNode|nil
local function get_scope(opts)
  local first, last = opts.first, opts.last

  -- An added function arrives with a blank line beside it, which would push the lookup out to the whole file
  while first < last and vim.trim(opts.lines[first] or "") == "" do
    first = first + 1
  end
  while last > first and vim.trim(opts.lines[last] or "") == "" do
    last = last - 1
  end

  local node = opts.root:named_descendant_for_range(first - 1, 0, last - 1, 0)
  while node do
    local kind = node:type()
    if kind:match("function") or kind:match("method") or kind:match("class") then
      return node
    end
    node = node:parent()
  end
end

---Neighbouring hunks as one row: those inside the same scope, or a `git diff` context apart outside one
---@param file_diff CC.Diff
---@return { hunks: number[], scope?: TSNode }[] groups
---@return { root: TSNode, source: string }|nil parsed
local function group_hunks(file_diff)
  local parsed = parse_working_file(file_diff)
  local groups = {}

  for index, hunk in ipairs(file_diff.hunks) do
    local first, last = working_span(hunk)
    local scope = parsed and get_scope({ root = parsed.root, lines = file_diff.to.lines, first = first, last = last })
    local previous = groups[#groups]

    local joins_previous = false
    if previous and scope and previous.scope then
      joins_previous = scope:equal(previous.scope)
    elseif previous then
      local _, previous_last = working_span(file_diff.hunks[index - 1])
      joins_previous = first - previous_last - 1 <= GROUP_GAP
    end

    if joins_previous then
      table.insert(previous.hunks, index)
    else
      table.insert(groups, { hunks = { index }, scope = scope or nil })
    end
  end

  return groups, parsed
end

---The working lines a scope node spans
---@param scope TSNode
---@return { first: number, last: number }
local function get_scope_lines(scope)
  local start_row, _, end_row, end_col = scope:range()
  return { first = start_row + 1, last = end_col == 0 and end_row or end_row + 1 }
end

---Does the group add the whole scope, meaning it did not exist before this round?
---@param opts { scope: TSNode, file_diff: CC.Diff, hunks: number[] }
---@return boolean
local function is_new_scope(opts)
  local lines = get_scope_lines(opts.scope)
  local first, last = lines.first, lines.last

  for _, index in ipairs(opts.hunks) do
    local hunk = opts.file_diff.hunks[index]
    if hunk.kind == "add" and hunk.to_start <= first and hunk.to_start + hunk.to_count - 1 >= last then
      return true
    end
  end

  return false
end

---The comments written against the lines a group now covers, give or take the grouping gap
---@param opts { comments: CodeCompanion.CodeReview.Comment[], path: string, file_diff: CC.Diff, hunks: number[] }
---@return string[]
local function get_nearby_comments(opts)
  local first = working_span(opts.file_diff.hunks[opts.hunks[1]])
  local _, last = working_span(opts.file_diff.hunks[opts.hunks[#opts.hunks]])

  local texts = {}
  for _, comment in ipairs(opts.comments) do
    local near = comment.start_line <= last + GROUP_GAP and comment.end_line >= first - GROUP_GAP
    if comment.path == opts.path and near then
      table.insert(texts, comment.comment)
    end
  end

  return texts
end

---The checklist row for a group of hunks, named for the scope they sit in when the parser knows it
---@param opts { file_diff: CC.Diff, group: { hunks: number[], scope?: TSNode }, source?: string, sent?: string[], explanation?: string }
---@return { text: string, spans: { added: number[], removed: number[] } }
local function summarise(opts)
  local file_diff = opts.file_diff

  local added, removed = 0, 0
  for _, index in ipairs(opts.group.hunks) do
    added = added + file_diff.hunks[index].to_count
    removed = removed + file_diff.hunks[index].from_count
  end

  local first = file_diff.hunks[opts.group.hunks[1]]
  local changed = first.to_count > 0 and file_diff.to.lines[first.to_start] or file_diff.from.lines[first.from_start]
  local label = vim.trim(changed or "")

  local scope = opts.group.scope
  local name = scope and scope:field("name")[1]
  if scope and name and opts.source then
    local relation = is_new_scope({ scope = scope, file_diff = file_diff, hunks = opts.group.hunks }) and "new" or "in"
    label = relation .. " " .. vim.treesitter.get_node_text(name, opts.source)
  end

  local added_text, removed_text = fmt("+%d", added), fmt("-%d", removed)
  local added_start = 2
  local removed_start = added_start + #added_text + 1

  local text = fmt("  %s %s  %s", added_text, removed_text, label)
  local spans = {
    added = { added_start, added_start + #added_text },
    removed = { removed_start, removed_start + #removed_text },
  }

  if opts.sent and #opts.sent > 0 then
    text = text .. " ↳"
    spans.sent = { #text - #"↳", #text }
  end

  if opts.explanation then
    local icon = vim.trim(config.interactions.code_review.display.explanations.icon)
    text = text .. " " .. icon
    spans.explanation = { #text - #icon, #text }
  end

  return { text = text, spans = spans }
end

---The checklist row for a file: its name, the lines left to review in it and any diagnostics against it
---@param opts { path: string, file_diff: CC.Diff, diagnostics: { errors: number, warnings: number } }
---@return { text: string, spans: table<string, number[]> }
local function summarise_file(opts)
  local added, removed = 0, 0
  for _, hunk in ipairs(opts.file_diff.hunks) do
    added = added + hunk.to_count
    removed = removed + hunk.from_count
  end

  local text = shorten_path(opts.path)
  local spans = { path = { 0, #text } }

  local function append(name, label, separator)
    text = text .. separator .. label
    spans[name] = { #text - #label, #text }
  end

  append("added", fmt("+%d", added), "  ")
  append("removed", fmt("-%d", removed), " ")

  local separator = "  "
  for _, severity in ipairs({ { "errors", "E" }, { "warnings", "W" } }) do
    local count = opts.diagnostics[severity[1]]
    if count > 0 then
      append(severity[1], severity[2] .. count, separator)
      separator = " "
    end
  end

  return { text = text, spans = spans }
end

---The baseline hunks still awaiting review, grouped by the file they belong to
---@param root string
---@return string[] paths
---@return table<string, CodeCompanion.CodeReview.Hunk[]> by_path
---@return number auto_accepted Files left out because the config says they never need reviewing
local function get_pending_hunks(root)
  local paths, by_path, auto_accepted = {}, {}, {}

  for _, git_hunk in ipairs(baseline.diff(root) or {}) do
    local path = git_hunk.path
    if is_auto_accepted(path) then
      auto_accepted[path] = true
    elseif not by_path[path] then
      by_path[path] = { git_hunk }
      table.insert(paths, path)
    else
      table.insert(by_path[path], git_hunk)
    end
  end

  return paths, by_path, vim.tbl_count(auto_accepted)
end

---@param count number
---@param noun string
---@return string
local function pluralise(count, noun)
  return fmt("%d %s%s", count, noun, count == 1 and "" or "s")
end

---The size of the round in one line, so the reviewer knows the shape of it before the detail
---@param opts { paths: string[], diffs: table<string, CC.Diff>, rows: number, diagnostics: table<string, { errors: number }>, auto_accepted: number }
---@return string
local function summarise_round(opts)
  local hunks, with_errors = 0, 0
  for _, path in ipairs(opts.paths) do
    hunks = hunks + #opts.diffs[path].hunks
    with_errors = with_errors + (opts.diagnostics[path].errors > 0 and 1 or 0)
  end

  local parts = { pluralise(#opts.paths, "file"), pluralise(hunks, "hunk") }
  if opts.rows < hunks then
    parts[#parts] = parts[#parts] .. " in " .. pluralise(opts.rows, "row")
  end
  if with_errors > 0 then
    table.insert(parts, with_errors .. " with errors")
  end
  if opts.auto_accepted > 0 then
    table.insert(parts, opts.auto_accepted .. " auto-accepted")
  end

  return table.concat(parts, ", ")
end

---Put the files most likely to need a human first: errors, then the most changed lines in the round
---@param opts { paths: string[], by_path: table<string, CodeCompanion.CodeReview.Hunk[]>, diagnostics: table<string, { errors: number }> }
---@return string[]
local function sort_by_risk(opts)
  -- Sized from the round's baseline hunks rather than what is left, so accepting a hunk never reorders the list
  local changed_lines = {}
  for _, path in ipairs(opts.paths) do
    changed_lines[path] = 0
    for _, git_hunk in ipairs(opts.by_path[path]) do
      changed_lines[path] = changed_lines[path] + git_hunk.added + git_hunk.removed
    end
  end

  table.sort(opts.paths, function(a, b)
    if opts.diagnostics[a].errors ~= opts.diagnostics[b].errors then
      return opts.diagnostics[a].errors > opts.diagnostics[b].errors
    end
    if changed_lines[a] ~= changed_lines[b] then
      return changed_lines[a] > changed_lines[b]
    end
    return a < b
  end)

  return opts.paths
end

---Build the checklist rows, the entry each row selects and the diff behind each file
---@param opts { root: string }
---@return { entries: CodeCompanion.CodeReview.Entry[], lines: string[], diffs: table<string, CC.Diff> }
function M.build(opts)
  local root = opts.root
  local accepted = store.accepted(root)
  local sent = store.sent(root)
  local explanations = store.explanations(root)
  local changed, by_path, auto_accepted = get_pending_hunks(root)

  local paths, diffs, diagnostics = {}, {}, {}
  for _, path in ipairs(changed) do
    local file_diff = build_diff({ root = root, path = path, accepted = accepted, git_hunks = by_path[path] })

    if #file_diff.hunks > 0 then
      diffs[path] = file_diff
      diagnostics[path] = count_diagnostics(root, path)
      table.insert(paths, path)
    else
      M.discard({ file_diff })
    end
  end

  local entries, lines = {}, {}
  if #paths == 0 then
    return { entries = entries, lines = lines, diffs = diffs }
  end

  local rows = 0
  for _, path in ipairs(sort_by_risk({ paths = paths, by_path = by_path, diagnostics = diagnostics })) do
    local summary = summarise_file({ path = path, file_diff = diffs[path], diagnostics = diagnostics[path] })
    table.insert(entries, { kind = "file", path = path, spans = summary.spans })
    table.insert(lines, summary.text)

    local groups, parsed = group_hunks(diffs[path])
    for _, group in ipairs(groups) do
      local nearby = { path = path, file_diff = diffs[path], hunks = group.hunks }
      local sent_here = get_nearby_comments(vim.tbl_extend("force", nearby, { comments = sent }))
      local explained = get_nearby_comments(vim.tbl_extend("force", nearby, { comments = explanations }))
      local summary = summarise({
        file_diff = diffs[path],
        group = group,
        source = parsed and parsed.source,
        sent = sent_here,
        explanation = explained[#explained],
      })

      local ids = {}
      for _, index in ipairs(group.hunks) do
        vim.list_extend(ids, get_baseline_ids({ git_hunks = by_path[path], hunk = diffs[path].hunks[index] }))
      end

      table.insert(entries, {
        kind = "hunk",
        path = path,
        hunks = group.hunks,
        ids = ids,
        sent = #sent_here > 0 and sent_here or nil,
        explanation = explained[#explained],
        spans = summary.spans,
      })
      table.insert(lines, summary.text)
      rows = rows + 1
    end
  end

  local header = summarise_round({
    paths = paths,
    diffs = diffs,
    rows = rows,
    diagnostics = diagnostics,
    auto_accepted = auto_accepted,
  })
  table.insert(entries, 1, { kind = "header", spans = { header = { 0, #header } } })
  table.insert(lines, 1, header)

  return { entries = entries, lines = lines, diffs = diffs }
end

return M
