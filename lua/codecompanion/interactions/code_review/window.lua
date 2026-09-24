local baseline = require("codecompanion.interactions.code_review.baseline")
local checklist = require("codecompanion.interactions.code_review.checklist")
local config = require("codecompanion.config")
local diff_ui = require("codecompanion.diff.ui")
local explain = require("codecompanion.interactions.code_review.explain")
local store = require("codecompanion.interactions.code_review.store")
local ui = require("codecompanion.interactions.code_review.ui")
local ui_utils = require("codecompanion.utils.ui")
local utils = require("codecompanion.utils")

local api = vim.api
local fmt = string.format

local CONSTANTS = {
  CHECKLIST_MAX_WIDTH = 42,
  EMPTY = "No edits left to review",
  FILETYPE = "codecompanion_code_review",
  GROUP = "codecompanion.code_review.window",
  CHECKLIST_NAME = "Code Review",
  PANE_NAME = "Code Review Diff",
  HL_ADDED = "CodeCompanionCodeReviewAdded",
  HL_EXPLANATION = "CodeCompanionCodeReviewExplanation",
  HL_HEADER = "CodeCompanionCodeReviewHeader",
  HL_PATH = "CodeCompanionCodeReviewPath",
  HL_REMOVED = "CodeCompanionCodeReviewRemoved",
  HL_SENT = "CodeCompanionCodeReviewSent",
  NAMESPACE = api.nvim_create_namespace("codecompanion.code_review.window"),
}

local SPAN_HIGHLIGHTS = {
  added = CONSTANTS.HL_ADDED,
  errors = "DiagnosticError",
  explanation = CONSTANTS.HL_EXPLANATION,
  header = CONSTANTS.HL_HEADER,
  path = CONSTANTS.HL_PATH,
  removed = CONSTANTS.HL_REMOVED,
  sent = CONSTANTS.HL_SENT,
  warnings = "DiagnosticWarn",
}

---@class CodeCompanion.CodeReview.Window.Undo
---@field accepted? string[] Hunk ids to take back out of the accepted set
---@field splices? { path: string, start: number, count: number, lines: string[] }[] Lines to put back, and where, top-down

---@class CodeCompanion.CodeReview.Window
---@field active_path? string
---@field asking table<string, boolean> Rows an explanation has been requested for, keyed by `path:first`
---@field checklist { bufnr: number, winnr: number }
---@field diffs table<string, CC.Diff>
---@field entries CodeCompanion.CodeReview.Entry[]
---@field origin_tabpage number The tab the review was opened from, where files are edited
---@field pane { bufnr: number, winnr: number } The code being reviewed
---@field root string
---@field syncing boolean
---@field tabpage number
---@field undo CodeCompanion.CodeReview.Window.Undo[]
---@field watcher? uv.uv_fs_event_t Watches the storage directory for an agent writing an explanation

-- Only ever indexed while a review is open, so the type says what the helpers can rely on
local review ---@type CodeCompanion.CodeReview.Window

local M = {}

---@return boolean
local function is_open()
  return review ~= nil and api.nvim_buf_is_valid(review.checklist.bufnr) and api.nvim_buf_is_valid(review.pane.bufnr)
end

---Stop tracking the review, leaving whatever is on screen as the user left it
---@return nil
local function forget()
  pcall(api.nvim_del_augroup_by_name, CONSTANTS.GROUP)
  checklist.discard(review.diffs)
  if review.watcher then
    review.watcher:stop()
    review.watcher:close()
  end

  -- If every hunk has been cleared then start the next round of review
  local reviewed = #review.entries == 0

  ---@diagnostic disable-next-line: cast-local-type
  review = nil

  if reviewed then
    require("codecompanion.interactions.code_review").mark_reviewed()
  end
end

---@param message string
---@param level? number A `vim.log.levels` value, defaulting to INFO
---@return nil
local function notify(message, level)
  return utils.notify(message, level or vim.log.levels.INFO, { title = "CodeCompanion Code Review" })
end

---@param winnr number
---@param bufnr number
---@param lines string[]
---@return nil
local function fill_panel(winnr, bufnr, lines)
  api.nvim_win_set_buf(winnr, bufnr)
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].swapfile = false
end

---@param panel { bufnr: number, winnr: number }
---@param lines string[]
---@return nil
local function replace_lines(panel, lines)
  vim.bo[panel.bufnr].modifiable = true
  api.nvim_buf_set_lines(panel.bufnr, 0, -1, false, lines)
  vim.bo[panel.bufnr].modifiable = false
end

---The review owns its own tab page, so `wincmd` and the window resize commands behave as they do anywhere else
---@param lines string[]
---@return { checklist: { bufnr: number, winnr: number }, pane: { bufnr: number, winnr: number }, tabpage: number }
local function open_panels(lines)
  vim.cmd("tabnew")
  local pane_winnr = api.nvim_get_current_win()

  vim.cmd("leftabove vsplit")
  local checklist_winnr = api.nvim_get_current_win()
  api.nvim_win_set_config(checklist_winnr, {
    width = math.min(CONSTANTS.CHECKLIST_MAX_WIDTH, math.floor(vim.o.columns / 3)),
  })

  local checklist_bufnr = api.nvim_create_buf(false, true)
  fill_panel(checklist_winnr, checklist_bufnr, lines)
  vim.bo[checklist_bufnr].filetype = CONSTANTS.FILETYPE
  pcall(api.nvim_buf_set_name, checklist_bufnr, CONSTANTS.CHECKLIST_NAME)

  local pane_bufnr = api.nvim_create_buf(false, true)
  fill_panel(pane_winnr, pane_bufnr, {})
  pcall(api.nvim_buf_set_name, pane_bufnr, CONSTANTS.PANE_NAME)

  -- A new window inherits the global gutter options, so every one of them is pinned here
  vim.wo[checklist_winnr].cursorline = true
  vim.wo[checklist_winnr].foldcolumn = "0"
  vim.wo[checklist_winnr].number = false
  vim.wo[checklist_winnr].relativenumber = false
  vim.wo[checklist_winnr].signcolumn = "no"
  vim.wo[checklist_winnr].statuscolumn = ""
  vim.wo[checklist_winnr].winfixwidth = true
  vim.wo[checklist_winnr].wrap = false

  vim.wo[pane_winnr].foldcolumn = "0"
  vim.wo[pane_winnr].number = false
  vim.wo[pane_winnr].relativenumber = false
  vim.wo[pane_winnr].signcolumn = "no"
  vim.wo[pane_winnr].statuscolumn = [[%!v:lua.require("codecompanion.interactions.code_review.window").statuscolumn()]]
  vim.wo[pane_winnr].wrap = false

  return {
    checklist = { bufnr = checklist_bufnr, winnr = checklist_winnr },
    pane = { bufnr = pane_bufnr, winnr = pane_winnr },
    tabpage = api.nvim_get_current_tabpage(),
  }
end

---Colour the path, counts and diagnostics on every checklist row
---@return nil
local function highlight_checklist()
  api.nvim_buf_clear_namespace(review.checklist.bufnr, CONSTANTS.NAMESPACE, 0, -1)

  for row, entry in ipairs(review.entries) do
    for name, span in pairs(entry.spans or {}) do
      api.nvim_buf_set_extmark(review.checklist.bufnr, CONSTANTS.NAMESPACE, row - 1, span[1], {
        end_col = span[2],
        hl_group = SPAN_HIGHLIGHTS[name],
      })
    end
  end
end

---The review pane row showing a given working line, so a comment can be drawn against it
---@param line number
---@return number|nil
local function pane_row_for(line)
  for row, mapped in ipairs(review.diffs[review.active_path].merged.rows) do
    if mapped.to == line then
      return row
    end
  end
end

---Draw the pending comments for the file on show against the rows they were written on
---@return nil
local function show_comments()
  ui.clear(review.pane.bufnr)
  if not review.active_path then
    return
  end

  for index, comment in ipairs(require("codecompanion.interactions.code_review").pending()) do
    local row = comment.path == review.active_path and pane_row_for(comment.start_line) or nil
    if row then
      ui.place_comment({ bufnr = review.pane.bufnr, row = row - 1, comment = comment.comment, index = index })
    end
  end
end

---Draw what the user asked for last round above the changes that answer it
---@return nil
local function show_sent()
  for _, entry in ipairs(review.entries) do
    if entry.path == review.active_path and entry.sent then
      local virt_lines = {}
      for _, comment in ipairs(entry.sent) do
        for index, line in ipairs(vim.split(comment, "\n", { plain = true })) do
          local prefix = index == 1 and "↳ You asked: " or string.rep(" ", #"↳ You asked: " - 2)
          table.insert(virt_lines, { { prefix .. line, CONSTANTS.HL_SENT } })
        end
      end

      local hunk = review.diffs[entry.path].hunks[entry.hunks[1]]
      api.nvim_buf_set_extmark(review.pane.bufnr, CONSTANTS.NAMESPACE, hunk.pos[1], 0, {
        virt_lines = virt_lines,
        virt_lines_above = true,
      })
    end
  end
end

---@param entry CodeCompanion.CodeReview.Entry
---@return string
local function asking_key(entry)
  return fmt("%s:%d", entry.path, review.diffs[entry.path].hunks[entry.hunks[1]].to_start)
end

---Draw the first line of each explanation above the change it describes, or that one has been asked for
---@return nil
local function show_explanations()
  local icon = config.interactions.code_review.display.explanations.icon
  for _, entry in ipairs(review.entries) do
    if entry.path == review.active_path and entry.hunks then
      local text
      if entry.explanation then
        text = vim.split(entry.explanation, "\n", { plain = true })[1]
      elseif review.asking[asking_key(entry)] then
        text = "asking for an explanation…"
      end

      if text then
        local hunk = review.diffs[entry.path].hunks[entry.hunks[1]]
        api.nvim_buf_set_extmark(review.pane.bufnr, CONSTANTS.NAMESPACE, hunk.pos[1], 0, {
          virt_lines = { { { icon .. text, CONSTANTS.HL_EXPLANATION } } },
          virt_lines_above = true,
        })
      end
    end
  end
end

---@param path string
---@return nil
local function show_file(path)
  if review.active_path == path then
    return
  end

  local file_diff = review.diffs[path]
  review.active_path = path

  replace_lines(review.pane, file_diff.merged.lines)
  vim.bo[review.pane.bufnr].filetype = file_diff.ft or "text"

  api.nvim_buf_clear_namespace(review.pane.bufnr, CONSTANTS.NAMESPACE, 0, -1)
  diff_ui.apply_highlights(file_diff, { bufnr = review.pane.bufnr, ns = CONSTANTS.NAMESPACE })
  show_sent()
  show_explanations()
  show_comments()
end

---@param winnr number
---@param row number
---@return nil
local function centre_on(winnr, row)
  pcall(api.nvim_win_set_cursor, winnr, { row, 0 })
  api.nvim_win_call(winnr, function()
    vim.cmd("normal! zz")
  end)
end

---The review pane row a hunk's first change sits on
---@param hunk CodeCompanion.diff.Hunk
---@return number
local function hunk_row(hunk)
  return hunk.pos[1] + 1
end

---The first hunk in a checklist row's group, which is where the row starts in the review pane
---@param entry CodeCompanion.CodeReview.Entry
---@return CodeCompanion.diff.Hunk
local function first_hunk(entry)
  return review.diffs[entry.path].hunks[entry.hunks[1]]
end

---Show the file a checklist row belongs to, scrolled to its hunk
---@param row number
---@return nil
local function select_entry(row)
  local entry = review.entries[row]
  if not entry or not entry.path then
    return
  end

  show_file(entry.path)

  centre_on(review.pane.winnr, entry.hunks and hunk_row(first_hunk(entry)) or 1)
end

---The checklist row for the last hunk the review pane's cursor has reached
---@param row number
---@return number|nil
local function checklist_row_for(row)
  local match
  for index, entry in ipairs(review.entries) do
    if entry.path == review.active_path and entry.hunks and hunk_row(first_hunk(entry)) <= row then
      match = index
    end
  end
  return match
end

---Move a panel's cursor as a sync, so the panel it is following does not answer it
---@param handler fun(): nil
---@return nil
local function sync_panels(handler)
  if review.syncing then
    return
  end
  review.syncing = true
  handler()
  review.syncing = false
end

---Redraw the checklist and the file alongside it, keeping the cursor where it was
---@return nil
local function rebuild()
  local built = checklist.build({ root = review.root })
  if vim.deep_equal(built.lines, api.nvim_buf_get_lines(review.checklist.bufnr, 0, -1, false)) then
    return checklist.discard(built.diffs)
  end

  local row = api.nvim_win_get_cursor(review.checklist.winnr)[1]

  checklist.discard(review.diffs)
  review.active_path = nil
  review.diffs = built.diffs
  review.entries = built.entries

  replace_lines(review.checklist, #built.lines > 0 and built.lines or { CONSTANTS.EMPTY })
  highlight_checklist()

  if #built.entries == 0 then
    review.active_path = nil
    replace_lines(review.pane, {})
    return api.nvim_buf_clear_namespace(review.pane.bufnr, CONSTANTS.NAMESPACE, 0, -1)
  end

  -- Row 1 is the header, which has no file to show
  sync_panels(function()
    row = math.max(2, math.min(row, #built.entries))
    pcall(api.nvim_win_set_cursor, review.checklist.winnr, { row, 0 })
    select_entry(row)
  end)
end

---Move the review pane to the next or previous checklist row in this file
---@param step number
---@return nil
local function jump_hunk(step)
  local row = api.nvim_win_get_cursor(review.pane.winnr)[1]

  local target
  for _, entry in ipairs(review.entries) do
    if entry.path == review.active_path and entry.hunks then
      local start = hunk_row(first_hunk(entry))
      if step > 0 and start > row then
        target = start
        break
      elseif step < 0 and start < row then
        target = start
      end
    end
  end

  if target then
    centre_on(review.pane.winnr, target)
  end
end

---The hunk literally under the cursor, in whichever panel the user is in
---@return CodeCompanion.CodeReview.Entry|nil
local function hunk_under_cursor()
  local winnr = api.nvim_get_current_win()

  if winnr == review.checklist.winnr then
    local entry = review.entries[api.nvim_win_get_cursor(winnr)[1]]
    return entry and entry.hunks and entry or nil
  end

  local row = api.nvim_win_get_cursor(winnr)[1]
  for _, entry in ipairs(review.entries) do
    for _, index in ipairs(entry.path == review.active_path and entry.hunks or {}) do
      local hunk = review.diffs[entry.path].hunks[index]
      if row > hunk.pos[1] and row <= hunk.pos[1] + hunk.from_count + hunk.to_count then
        return entry
      end
    end
  end
end

---The file row the cursor is on, which stands for every hunk in that file
---@return string|nil
local function file_under_cursor()
  if api.nvim_get_current_win() ~= review.checklist.winnr then
    return
  end

  local entry = review.entries[api.nvim_win_get_cursor(review.checklist.winnr)[1]]
  return entry and entry.kind == "file" and entry.path or nil
end

---@param path string
---@return CodeCompanion.CodeReview.Entry[]
local function hunks_in(path)
  return vim.tbl_filter(function(entry)
    return entry.path == path and entry.hunks ~= nil
  end, review.entries)
end

---Keep the hunks, so the review stops showing them from now on
---@param entries CodeCompanion.CodeReview.Entry[]
---@return nil
local function accept_hunks(entries)
  local ids = {}
  for _, entry in ipairs(entries) do
    vim.list_extend(ids, entry.ids or {})
  end

  if #ids == 0 then
    return notify("Could not match this change against the baseline", vim.log.levels.WARN)
  end

  for _, id in ipairs(ids) do
    store.accept(review.root, id)
  end

  -- One undo entry for the lot, so `u` takes back a whole file in one go
  table.insert(review.undo, { accepted = ids })
  rebuild()
end

---Put the working file's lines back to the baseline for every hunk in a checklist row
---@param entry CodeCompanion.CodeReview.Entry
---@return nil
local function revert_hunks(entry)
  local file_diff = review.diffs[entry.path]

  local bufnr = vim.fn.bufadd(vim.fs.joinpath(review.root, entry.path))
  vim.fn.bufload(bufnr)

  if vim.bo[bufnr].modified then
    return notify(fmt("`%s` has unsaved changes", entry.path), vim.log.levels.WARN)
  end

  -- Bottom-up, so each splice leaves the working line numbers of the hunks above it intact
  local splices = {}
  for position = #entry.hunks, 1, -1 do
    local hunk = file_diff.hunks[entry.hunks[position]]
    local at = hunk.to_count > 0 and hunk.to_start or hunk.to_start + 1
    local restored = vim.list_slice(file_diff.from.lines, hunk.from_start, hunk.from_start + hunk.from_count - 1)
    local replaced = api.nvim_buf_get_lines(bufnr, at - 1, at - 1 + hunk.to_count, false)

    api.nvim_buf_set_lines(bufnr, at - 1, at - 1 + hunk.to_count, false, restored)
    table.insert(splices, 1, { path = entry.path, start = at, count = #restored, lines = replaced })
  end

  -- The buffer stays loaded so the file's own undo history holds the revert, and `noautocmd`
  -- stops a format-on-save autocmd rewriting what was just put back
  api.nvim_buf_call(bufnr, function()
    vim.cmd("silent noautocmd write")
  end)

  table.insert(review.undo, { splices = splices })
  rebuild()
end

---Take back the last accept or revert
---@return nil
local function undo_last()
  local last = table.remove(review.undo)
  if not last then
    return
  end

  for _, id in ipairs(last.accepted or {}) do
    store.unaccept(review.root, id)
  end

  -- Top-down puts each hunk back at the working line it was reverted from, before the ones below it move
  for _, splice in ipairs(last.splices or {}) do
    local bufnr = vim.fn.bufadd(vim.fs.joinpath(review.root, splice.path))
    vim.fn.bufload(bufnr)

    local at = splice.start - 1
    api.nvim_buf_set_lines(bufnr, at, at + splice.count, false, splice.lines)
    api.nvim_buf_call(bufnr, function()
      vim.cmd("silent noautocmd write")
    end)
  end

  rebuild()
end

---Move out of the review tab, so opening a file cannot replace one of its panels
---@return nil
local function leave_review()
  if api.nvim_tabpage_is_valid(review.origin_tabpage) and review.origin_tabpage ~= review.tabpage then
    return api.nvim_set_current_tabpage(review.origin_tabpage)
  end
  vim.cmd("tabnew")
end

---Open the working file at the row under the cursor, in the tab the review was opened from
---@return nil
local function edit_line()
  local rows = review.diffs[review.active_path].merged.rows
  local cursor = api.nvim_win_get_cursor(review.pane.winnr)[1]

  -- A deleted row has no line in the working file, so edit the nearest one below it
  local line
  for offset = cursor, #rows do
    line = rows[offset] and rows[offset].to
    if line then
      break
    end
  end

  local path = vim.fs.joinpath(review.root, review.active_path)

  leave_review()
  vim.cmd.edit(vim.fn.fnameescape(path))
  pcall(api.nvim_win_set_cursor, 0, { line or 1, 0 })
  vim.cmd("startinsert")
end

---The working line the cursor sits on, or the line a checklist hunk starts at
---@return number|nil
local function commented_line()
  if api.nvim_get_current_win() == review.checklist.winnr then
    local entry = review.entries[api.nvim_win_get_cursor(review.checklist.winnr)[1]]
    return entry and entry.hunks and math.max(first_hunk(entry).to_start, 1) or nil
  end

  local rows = review.diffs[review.active_path].merged.rows
  local row = rows[api.nvim_win_get_cursor(review.pane.winnr)[1]]

  -- A deleted row has no line in the working file, so the comment lands on the line it sat after
  return row and (row.to or row.from) or nil
end

---Comment on the line under the cursor, or change the comment already there
---@return nil
local function comment_on_line()
  local code_review = require("codecompanion.interactions.code_review")

  if api.nvim_get_current_win() == review.pane.winnr then
    local existing = ui.comment_at(review.pane.bufnr, api.nvim_win_get_cursor(review.pane.winnr)[1])
    if existing then
      return code_review.edit_comment(existing, { on_done = show_comments })
    end
  end

  local line = commented_line()
  if not line then
    return notify("Nothing to comment on here", vim.log.levels.WARN)
  end

  local path = review.active_path
  local lines = checklist.read_file_lines(review.root, path)

  code_review.add_comment({
    code = lines[line] or "",
    filetype = vim.filetype.match({ filename = vim.fs.joinpath(review.root, path) }),
    path = path,
    start_line = line,
    end_line = line,
  }, { on_done = show_comments })
end

---The change on a row as `-`/`+` lines with the working code around it, for a model that cannot read the repo
---@param entry CodeCompanion.CodeReview.Entry
---@return string
local function snippet_for(entry)
  local file_diff = review.diffs[entry.path]
  local lines = {}

  local first = file_diff.hunks[entry.hunks[1]]
  local last = file_diff.hunks[entry.hunks[#entry.hunks]]
  local from, to = math.max(first.to_start - 10, 1), math.min(last.to_start + last.to_count + 9, #file_diff.to.lines)

  for line = from, to do
    table.insert(lines, "  " .. file_diff.to.lines[line])
  end
  for _, index in ipairs(entry.hunks) do
    local hunk = file_diff.hunks[index]
    for line = hunk.from_start, hunk.from_start + hunk.from_count - 1 do
      table.insert(lines, "- " .. file_diff.from.lines[line])
    end
    for line = hunk.to_start, hunk.to_start + hunk.to_count - 1 do
      table.insert(lines, "+ " .. file_diff.to.lines[line])
    end
  end

  return table.concat(lines, "\n")
end

---Ask the agent to explain the row under the cursor, or show the explanation it already gave
---@return nil
local function explain_row()
  local entry = hunk_under_cursor()
  if not entry then
    return notify("Nothing to explain here", vim.log.levels.WARN)
  end

  if entry.explanation then
    local lines = vim.split(entry.explanation, "\n", { plain = true })
    return ui_utils.create_float(lines, {
      ft = "markdown",
      height = math.min(#lines + 2, 20),
      lock = true,
      relative = "cursor",
      style = "minimal",
      title = "Explanation",
      width = 80,
    })
  end

  local file_diff = review.diffs[entry.path]
  local first = file_diff.hunks[entry.hunks[1]]
  local last = file_diff.hunks[entry.hunks[#entry.hunks]]
  local path = entry.path

  explain.ask({
    root = review.root,
    path = path,
    first = math.max(first.to_start, 1),
    last = math.max(last.to_start + last.to_count - 1, 1),
    snippet = snippet_for(entry),
  }, {
    on_asked = function()
      if not is_open() then
        return
      end
      review.asking[asking_key(entry)] = true
      review.active_path = nil
      show_file(path)
    end,
    on_done = function()
      if is_open() then
        rebuild()
      end
    end,
  })
end

---Show the window's keymaps in a float
---@return nil
local function show_keymaps()
  local rows = {}
  for _, map in pairs(config.interactions.code_review.keymaps or {}) do
    local keys = type(map) == "table" and map.visible ~= false and map.modes and map.modes.n or nil
    if keys then
      keys = vim.tbl_map(function(key)
        return fmt("`%s`", key)
      end, type(keys) == "table" and keys or { keys })
      table.insert(rows, { keys = table.concat(keys, " or "), description = map.description })
    end
  end

  table.sort(rows, function(a, b)
    return a.keys < b.keys
  end)

  local width = 0
  for _, row in ipairs(rows) do
    width = math.max(width, #row.keys)
  end

  local lines = { "### Keymaps", "" }
  for _, row in ipairs(rows) do
    table.insert(lines, fmt(" %s%s_%s_", row.keys, string.rep(" ", width - #row.keys + 4), row.description))
  end

  ui_utils.create_float(lines, {
    ft = "markdown",
    height = #lines + 2,
    lock = true,
    relative = "editor",
    style = "minimal",
    title = "Code Review",
    width = width + 60,
  })
end

local ACTIONS = {
  accept = function()
    local entry = hunk_under_cursor()
    if entry then
      return accept_hunks({ entry })
    end

    local path = file_under_cursor()
    return path and accept_hunks(hunks_in(path))
  end,
  close = function()
    return M.close()
  end,
  comment = comment_on_line,
  comments = function()
    leave_review()
    return require("codecompanion.interactions.code_review").edit_comments()
  end,
  edit = edit_line,
  explain = explain_row,
  keymaps = show_keymaps,
  next_hunk = function()
    return jump_hunk(1)
  end,
  previous_hunk = function()
    return jump_hunk(-1)
  end,
  revert = function()
    local entry = hunk_under_cursor()
    return entry and revert_hunks(entry)
  end,
  share = function()
    return require("codecompanion.interactions.code_review").share()
  end,
  undo = undo_last,
}

---@return nil
local function set_keymaps()
  for _, map in pairs(config.interactions.code_review.keymaps or {}) do
    local keys = type(map) == "table" and map.modes and map.modes.n or nil
    local action = keys and map.callback or nil

    if type(action) == "string" then
      action = ACTIONS[action]
    end

    if action then
      for _, key in ipairs(type(keys) == "table" and keys or { keys }) do
        for _, panel in ipairs({ review.checklist, review.pane }) do
          vim.keymap.set("n", key, action, { buffer = panel.bufnr, desc = map.description, nowait = true })
        end
      end
    end
  end
end

---@return nil
local function setup_sync()
  local group = api.nvim_create_augroup(CONSTANTS.GROUP, { clear = true })

  api.nvim_create_autocmd("CursorMoved", {
    desc = "Jump the review pane to the hunk selected in the checklist",
    group = group,
    buffer = review.checklist.bufnr,
    callback = function()
      if not is_open() then
        return forget()
      end
      sync_panels(function()
        select_entry(api.nvim_win_get_cursor(review.checklist.winnr)[1])
      end)
    end,
  })

  api.nvim_create_autocmd("CursorMoved", {
    desc = "Follow the review pane's scrolling in the checklist",
    group = group,
    buffer = review.pane.bufnr,
    callback = function()
      if not is_open() then
        return forget()
      end
      local row = checklist_row_for(api.nvim_win_get_cursor(review.pane.winnr)[1])
      if not row then
        return
      end
      sync_panels(function()
        pcall(api.nvim_win_set_cursor, review.checklist.winnr, { row, 0 })
      end)
    end,
  })

  api.nvim_create_autocmd("TabEnter", {
    desc = "Pick up the edits made while the review was in another tab",
    group = group,
    callback = function()
      if is_open() and api.nvim_get_current_tabpage() == review.tabpage then
        rebuild()
      end
    end,
  })

  -- An agent writes its explanation from outside Neovim, so a file watcher is the only cue to redraw
  local storage_dir = vim.fs.dirname(store.explanations_path(review.root))
  if vim.uv.fs_stat(storage_dir) then
    review.watcher = vim.uv.new_fs_event()
    review.watcher:start(
      storage_dir,
      {},
      vim.schedule_wrap(function()
        if is_open() then
          rebuild()
        end
      end)
    )
  end

  api.nvim_create_autocmd("TabClosed", {
    desc = "Forget the review once its tab page has gone",
    group = group,
    callback = function()
      if review and not api.nvim_tabpage_is_valid(review.tabpage) then
        forget()
      end
    end,
  })
end

---The working file's line number for the review pane row being drawn, blank on a deleted line
---@return string
function M.statuscolumn()
  if not review or not review.active_path then
    return ""
  end

  local row = review.diffs[review.active_path].merged.rows[vim.v.lnum]
  return fmt("%4s ", row and row.to or "")
end

---@return nil
function M.close()
  if not review then
    return
  end

  local tabpage = review.tabpage
  forget()

  if api.nvim_tabpage_is_valid(tabpage) then
    pcall(vim.cmd.tabclose, api.nvim_tabpage_get_number(tabpage))
  end
end

---Open the changed files and their hunks alongside the whole file they belong to
---@return nil
function M.open()
  local root = baseline.get_root()
  if not root or not baseline.get(root) then
    return notify("No edits to review yet", vim.log.levels.WARN)
  end

  M.close()

  local built = checklist.build({ root = root })
  if #built.entries == 0 then
    return notify("No edits to review")
  end

  local origin_tabpage = api.nvim_get_current_tabpage()
  local panels = open_panels(built.lines)

  review = {
    asking = {},
    checklist = panels.checklist,
    diffs = built.diffs,
    entries = built.entries,
    origin_tabpage = origin_tabpage,
    pane = panels.pane,
    root = root,
    syncing = false,
    tabpage = panels.tabpage,
    undo = {},
  }

  highlight_checklist()
  set_keymaps()
  setup_sync()

  sync_panels(function()
    pcall(api.nvim_win_set_cursor, review.checklist.winnr, { 2, 0 })
    select_entry(2)
  end)
  api.nvim_set_current_win(review.checklist.winnr)
end

return M
