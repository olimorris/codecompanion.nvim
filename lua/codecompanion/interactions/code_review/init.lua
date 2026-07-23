local baseline = require("codecompanion.interactions.code_review.baseline")
local config = require("codecompanion.config")
local files = require("codecompanion.utils.files")
local input = require("codecompanion.interactions.shared.input")
local keymaps = require("codecompanion.interactions.code_review.keymaps")
local log = require("codecompanion.utils.log")
local store = require("codecompanion.interactions.code_review.store")
local utils = require("codecompanion.utils")

local api = vim.api
local fmt = string.format

local M = {}

---@param message string
---@param level? number A `vim.log.levels` value, defaulting to INFO
---@return nil
local function notify(message, level)
  return utils.notify(message, level or vim.log.levels.INFO, { title = "CodeCompanion Code Review" })
end

---@return string
local function get_storage_root()
  return baseline.get_root() or vim.fs.normalize(vim.uv.cwd() or "")
end

---Fetch the context of where the use is commenting in the buffer
---@param bufnr number
---@param args? table
---@return { code: string, filetype: string, path: string, start_line: number, end_line: number }
local function get_context(bufnr, args)
  local buffer_context = require("codecompanion.utils.context").get(bufnr, args)
  local lines = buffer_context.lines

  if not buffer_context.is_visual then
    lines = api.nvim_buf_get_lines(bufnr, buffer_context.start_line - 1, buffer_context.start_line, false)
  end

  return {
    code = table.concat(lines, "\n"),
    filetype = buffer_context.filetype,
    path = buffer_context.relative_path,
    start_line = buffer_context.start_line,
    end_line = buffer_context.end_line,
  }
end

---Open the user input to add a comment
---@param context table
---@return nil
local function add_comment(context)
  input.open({
    title = " Add Comment ",
    on_submit = function(comment)
      local root = get_storage_root()
      store.add_comment(root, vim.tbl_extend("force", context, { comment = comment }))
      notify(fmt("Added comment (%d pending)", #store.comments(root)))
    end,
  })
end

---Review the entry in the quickfix list
---@return table|nil entry, number index, table list
local function get_qf_entry()
  local list = vim.fn.getqflist({ idx = 0, items = true })

  local index = list.idx
  if vim.bo.buftype == "quickfix" then
    index = api.nvim_win_get_cursor(0)[1]
  end

  local entry = list.items[index]
  if not (entry and type(entry.user_data) == "table" and entry.user_data.code_review_hunk) then
    return notify("No review hunk under the cursor", vim.log.levels.WARN)
  end

  return entry, index, list
end

---Comment on the hunk under the cursor in the quickfix list
---@return nil
local function comment_on_entry()
  local entry = get_qf_entry()
  if not entry then
    return
  end

  local filename = api.nvim_buf_get_name(entry.bufnr)

  -- The review diffs the files on disk, so read the commented line from there too
  local line = vim.fn.filereadable(filename) == 1 and vim.fn.readfile(filename)[entry.lnum] or ""

  local context = {
    code = line,
    filetype = vim.filetype.match({ filename = filename }),
    path = vim.fs.relpath(get_storage_root(), filename) or filename,
    start_line = entry.lnum,
    end_line = entry.lnum,
  }

  add_comment(context)
end

---Advance the baseline so only changes made from now on appear in a review
---@param root string
---@return nil
local function advance_baseline(root)
  if baseline.get_root() then
    baseline.snapshot(root)
  end
  store.clear_edited(root)
  store.clear_accepted(root)
  store.clear_ignored(root)
  keymaps.restore()
end

---Replace the review quickfix list, keeping the cursor on a nearby entry
---@param items table[]
---@param index number
---@return nil
local function replace_quickfix(items, index)
  local replacement = { items = items }
  if #items > 0 then
    replacement.idx = math.min(index, #items)
  end
  vim.fn.setqflist({}, "r", replacement)

  if #items == 0 then
    notify("All hunks reviewed")
  end
end

---Comment on the current line, visual selection or quickfix hunk
---@param args? table
---@return nil
function M.comment(args)
  if not config.can_send_code() then
    return log:warn("Sending of code has been disabled")
  end

  if vim.bo.buftype == "quickfix" then
    return comment_on_entry()
  end

  local context = get_context(api.nvim_get_current_buf(), args)
  add_comment(context)
end

---Return all pending review comments
---@return CodeCompanion.CodeReview.Comment[]
function M.pending()
  return store.comments(get_storage_root())
end

---Drain the pending comments for sending to the LLM, marking the review complete
---@return CodeCompanion.CodeReview.Comment[]|nil
function M.consume()
  local root = get_storage_root()
  local pending = store.comments(root)
  if #pending == 0 then
    return nil
  end

  store.clear_comments(root)
  advance_baseline(root)

  return pending
end

---Write the review to a file so it can be shared with an agent outside of CodeCompanion
---@return nil
function M.share()
  local root = get_storage_root()
  if #store.comments(root) == 0 then
    return notify("No comments to share", vim.log.levels.WARN)
  end

  local path = store.submit(root)
  if not path then
    return
  end

  advance_baseline(root)
  vim.fn.setreg("+", path)
  notify(fmt("Code review ready at `%s` (path copied to the clipboard)", path))
end

---Approve all changes up to now without comments
---@return nil
function M.approve()
  local root = get_storage_root()

  local pending = #store.comments(root)
  if pending > 0 then
    notify(fmt("%d pending comment(s) kept", pending), vim.log.levels.WARN)
  end

  advance_baseline(root)
  notify("Baseline set. Tracking agent changes from here")
end

---Open the changes since the baseline in the quickfix list, one entry per hunk
---@param opts? { scope?: "all" }
---@return nil
function M.open(opts)
  opts = opts or {}

  local root = baseline.get_root()
  if not root then
    -- Handle for non it repos
    return require("codecompanion.interactions.shared.edited_files").to_quickfix()
  end

  if not baseline.get(root) then
    return notify("No edits to review yet", vim.log.levels.WARN)
  end

  local paths = nil
  if opts.scope ~= "all" then
    paths = store.edited(root)
    if #paths == 0 then
      return notify(
        "No edits to review. Use `:CodeCompanionCodeReview All` to review everything since the baseline",
        vim.log.levels.WARN
      )
    end
  end

  local hunks = baseline.diff(root, paths)

  if opts.scope ~= "all" then
    local accepted = store.accepted(root)
    local ignored = store.ignored(root)
    hunks = vim.tbl_filter(function(hunk)
      return not accepted[tostring(hunk.id)] and not ignored[hunk.path]
    end, hunks)
  end

  if #hunks == 0 then
    return notify("No edits to review")
  end

  local items = {}
  for _, hunk in ipairs(hunks) do
    table.insert(items, {
      filename = vim.fs.joinpath(root, hunk.path),
      lnum = hunk.line,
      text = hunk.summary,
      user_data = { code_review_hunk = hunk.id },
    })
  end

  -- A new list is pushed onto the stack, so :colder restores the user's own list
  vim.fn.setqflist({}, " ", { title = "CodeCompanion Code Review", items = items })
  vim.cmd.copen()

  keymaps.set(api.nvim_get_current_buf())
end

---Accept the current quickfix hunk, keeping it out of the review from now on
---@return nil
function M.accept()
  local entry, index, list = get_qf_entry()
  if not entry then
    return
  end

  store.accept(get_storage_root(), entry.user_data.code_review_hunk)

  table.remove(list.items, index)
  replace_quickfix(list.items, index)
end

---Ignore the current hunk's file until the baseline advances
---@return nil
function M.ignore()
  local entry, index, list = get_qf_entry()
  if not entry then
    return
  end

  local root = get_storage_root()
  local path = vim.fs.relpath(root, api.nvim_buf_get_name(entry.bufnr))
  if not path then
    return
  end

  store.ignore(root, path)
  notify(fmt("Ignoring `%s`", path))

  replace_quickfix(
    vim.tbl_filter(function(item)
      return item.bufnr ~= entry.bufnr
    end, list.items),
    index
  )
end

---Open the pending comments file for editing by hand
---@return nil
function M.edit_comments()
  local path = store.comments_path(get_storage_root())
  if not files.exists(path) then
    return notify("No pending review comments", vim.log.levels.WARN)
  end

  -- Escape any '%' chars
  vim.cmd.edit(vim.fn.fnameescape(path))
end

---@return nil
function M.setup()
  if config.interactions.code_review.disabled then
    return
  end

  local group = api.nvim_create_augroup("codecompanion.code_review", { clear = true })

  api.nvim_create_autocmd("User", {
    desc = "Snapshot the review baseline before an agent starts editing",
    group = group,
    pattern = { "CodeCompanionChatSubmitted", "CodeCompanionCLISent" },
    callback = function()
      local root = baseline.get_root()
      if root and not baseline.get(root) then
        baseline.snapshot(root)
      end
    end,
  })

  api.nvim_create_autocmd("User", {
    desc = "Track the files an agent edits for review",
    group = group,
    pattern = "CodeCompanionFileEdited",
    callback = function(args)
      local root = baseline.get_root()
      if root and args.data and args.data.path then
        store.track(root, args.data.path)
      end
    end,
  })
end

return M
