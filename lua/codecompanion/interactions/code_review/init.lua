local baseline = require("codecompanion.interactions.code_review.baseline")
local config = require("codecompanion.config")
local files = require("codecompanion.utils.files")
local input = require("codecompanion.interactions.shared.input")
local log = require("codecompanion.utils.log")
local store = require("codecompanion.interactions.code_review.store")
local ui = require("codecompanion.interactions.code_review.ui")
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

local get_storage_root = baseline.storage_root --[[@as function]]

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
    path = vim.fs.relpath(get_storage_root(), buffer_context.path) or buffer_context.path,
    start_line = buffer_context.start_line,
    end_line = buffer_context.end_line,
  }
end

---Open the user input to change a comment already written against a line
---@param existing { comment: CodeCompanion.CodeReview.Comment, index: number }
---@param opts? { on_done?: fun(): nil }
---@return nil
function M.edit_comment(existing, opts)
  opts = opts or {}

  input.open({
    allow_empty = true, -- An empty submission deletes the comment
    initial_content = existing.comment.comment,
    title = " Edit Comment ",
    on_submit = function(comment)
      local root = get_storage_root()
      local comments = store.comments(root)

      if vim.trim(comment) == "" then
        table.remove(comments, existing.index)
      else
        comments[existing.index].comment = comment
      end

      store.write_comments(root, comments)
      ui.refresh()

      if opts.on_done then
        opts.on_done()
      end
    end,
  })
end

---Is there work the user hasn't reviewed yet?
---@param root string
---@return boolean
local function awaiting_review(root)
  return store.round_open(root) or #store.comments(root) > 0
end

---Open the user input to add a comment against a line
---@param context { code: string, filetype: string, path: string, start_line: number, end_line: number }
---@param opts? { on_done?: fun(): nil }
---@return nil
function M.add_comment(context, opts)
  opts = opts or {}

  input.open({
    title = " Add Comment ",
    on_submit = function(comment)
      store.add_comment(get_storage_root(), vim.tbl_extend("force", context, { comment = comment }))
      ui.refresh()

      if opts.on_done then
        opts.on_done()
      end
    end,
  })
end

---Close the round off, so only changes made from now on appear in a review
---@return boolean success
function M.mark_reviewed()
  local root = get_storage_root()

  if baseline.get_root() and not baseline.snapshot(root) then
    notify("Could not save your review. These changes will show up again next time", vim.log.levels.ERROR)
    return false
  end

  store.clear_round(root)
  store.clear_accepted(root)
  store.clear_sent(root)
  store.clear_explanations(root)
  return true
end

---Comment on the current line or visual selection
---@param args? table
---@return nil
function M.comment(args)
  if not config.can_send_code() then
    return log:warn("Sending of code has been disabled")
  end

  local bufnr = api.nvim_get_current_buf()

  local existing = ui.comment_at(bufnr, api.nvim_win_get_cursor(0)[1])
  if existing then
    return M.edit_comment(existing)
  end

  M.add_comment(get_context(bufnr, args))
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
  M.mark_reviewed()
  store.write_sent(root, pending)
  ui.clear_all()

  return pending
end

---Write the review to a file so it can be shared with an agent outside of CodeCompanion
---@return nil
function M.share()
  local root = get_storage_root()
  local comments = store.comments(root)
  if #comments == 0 then
    return notify("No comments to share", vim.log.levels.WARN)
  end

  local path = store.submit(root)
  if not path then
    return
  end

  M.mark_reviewed()
  store.write_sent(root, comments)
  ui.clear_all()
  vim.fn.setreg("+", path)
  notify(fmt("Code review ready at `%s` (path copied to the clipboard)", path))
end

---Open the review window, changed files on the left and the whole file on the right
---@return nil
function M.open_window()
  return require("codecompanion.interactions.code_review.window").open()
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

  ui.watch_for_comments(api.nvim_get_current_buf())
end

---@return nil
function M.setup()
  if not config.interactions.code_review.enabled then
    return
  end

  local group = api.nvim_create_augroup("codecompanion.code_review", { clear = true })

  api.nvim_create_autocmd("User", {
    desc = "Snapshot the review baseline at the start of an agent's edits",
    group = group,
    pattern = { "CodeCompanionChatSubmitted", "CodeCompanionCLISent", "CodeCompanionCLISubmitted" },
    callback = function(args)
      local root = baseline.get_root()
      if not root then
        return
      end

      -- Only take a snapshot if the user has finished reviewing the last round
      if not awaiting_review(root) then
        baseline.snapshot(root)
      end

      if baseline.get(root) then
        store.begin_round(root)
      end

      local bufnr = type(args.data) == "table" and args.data.bufnr or nil
      if bufnr and baseline.get(root) then
        local kind = args.match == "CodeCompanionChatSubmitted" and "chat" or "cli"
        store.set_round_channel(root, { kind = kind, bufnr = bufnr })
      end
    end,
  })

  api.nvim_create_autocmd("User", {
    desc = "Re-baseline on the next prompt when the agent changed no files",
    group = group,
    pattern = { "CodeCompanionChatDone", "CodeCompanionCLIDone" },
    callback = function()
      local root = baseline.get_root()
      if root and store.round_open(root) and baseline.worktree_matches(root) then
        store.clear_round(root)
      end
    end,
  })

  ui.refresh()
end

return M
