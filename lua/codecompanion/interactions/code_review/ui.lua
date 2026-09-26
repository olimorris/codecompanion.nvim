local baseline = require("codecompanion.interactions.code_review.baseline")
local config = require("codecompanion.config")
local store = require("codecompanion.interactions.code_review.store")

local api = vim.api

local CONSTANTS = {
  COMMENTS_FILE_GROUP = "codecompanion.code_review.comments_file",
  FILES_GROUP = "codecompanion.code_review.files",
  HL_GROUP = "CodeCompanionCodeReviewComment",
  NAMESPACE = api.nvim_create_namespace("codecompanion.code_review"),
}

local M = {}

---Where a rendered comment sits in the store, keyed by buffer then extmark
---@type table<number, table<number, number>>
local anchors = {}

---@return table
local function display()
  return config.interactions.code_review.display.comments
end

---Watch for files being opened, for only as long as there are comments to draw into them
---@param pending boolean
---@return nil
local function watch(pending)
  if not pending then
    pcall(api.nvim_del_augroup_by_name, CONSTANTS.FILES_GROUP)
    pcall(api.nvim_del_augroup_by_name, CONSTANTS.COMMENTS_FILE_GROUP)
    return
  end

  api.nvim_create_autocmd("BufReadPost", {
    desc = "Show the pending review comments in the file they were written against",
    group = api.nvim_create_augroup(CONSTANTS.FILES_GROUP, { clear = true }),
    callback = function(args)
      M.render(args.buf)
    end,
  })
end

---Redraw the comments whenever the buffer holding the comments file is written
---@param bufnr number
---@return nil
function M.watch_for_comments(bufnr)
  api.nvim_create_autocmd("BufWritePost", {
    desc = "Redraw the review comments after they've been edited by hand",
    buffer = bufnr,
    group = api.nvim_create_augroup(CONSTANTS.COMMENTS_FILE_GROUP, { clear = true }),
    callback = function()
      M.refresh()
    end,
  })
end

---@class CodeCompanion.CodeReview.Pending
---@field comments CodeCompanion.CodeReview.Comment[]
---@field root string

---Read the pending comments, resolved once per redraw and shared by every buffer drawn from it
---@return CodeCompanion.CodeReview.Pending
local function pending_comments()
  local root = baseline.storage_root()
  return { comments = store.comments(root), root = root }
end

---The comments written against the file a buffer is showing, paired with their store index
---@param bufnr number
---@param review CodeCompanion.CodeReview.Pending
---@return { comment: CodeCompanion.CodeReview.Comment, index: number }[]
local function comments_in(bufnr, review)
  local name = api.nvim_buf_get_name(bufnr)
  if name == "" then
    return {}
  end

  local path = vim.fs.relpath(review.root, name)
  if not path then
    return {}
  end

  local found = {}
  for index, comment in ipairs(review.comments) do
    if comment.path == path then
      table.insert(found, { comment = comment, index = index })
    end
  end

  return found
end

---@param opts { bufnr: number, row: number, comment: string, index: number }
---@return nil
function M.place_comment(opts)
  if not display().enabled then
    return
  end

  local virt_lines = {}
  for _, line in ipairs(vim.split(opts.comment, "\n", { plain = true })) do
    table.insert(virt_lines, { { display().icon .. line, CONSTANTS.HL_GROUP } })
  end

  -- Row is 0-indexed
  local id = api.nvim_buf_set_extmark(opts.bufnr, CONSTANTS.NAMESPACE, opts.row, 0, {
    virt_lines = virt_lines,
    virt_lines_above = true,
    virt_lines_overflow = display().overflow,
  })

  anchors[opts.bufnr] = anchors[opts.bufnr] or {}
  anchors[opts.bufnr][id] = opts.index
end

---Draw the comments a review holds into a buffer
---@param bufnr number
---@param review CodeCompanion.CodeReview.Pending
---@return nil
local function draw(bufnr, review)
  M.clear(bufnr)
  if not display().enabled or not api.nvim_buf_is_loaded(bufnr) then
    return
  end

  local last_line = api.nvim_buf_line_count(bufnr)

  for _, entry in ipairs(comments_in(bufnr, review)) do
    M.place_comment({
      bufnr = bufnr,
      comment = entry.comment.comment,
      index = entry.index,
      row = math.min(entry.comment.start_line, last_line) - 1,
    })
  end
end

---Remove the rendered comments from a buffer
---@param bufnr number
---@return nil
function M.clear(bufnr)
  if api.nvim_buf_is_valid(bufnr) then
    api.nvim_buf_clear_namespace(bufnr, CONSTANTS.NAMESPACE, 0, -1)
  end
  anchors[bufnr] = nil
end

---Draw the pending comments above the lines they were written against
---@param bufnr number
---@return nil
function M.render(bufnr)
  draw(bufnr, pending_comments())
end

---Redraw every loaded buffer, so a change to the store is reflected everywhere
---@return nil
function M.refresh()
  local review = pending_comments()
  watch(#review.comments > 0)

  for bufnr, _ in pairs(anchors) do
    if not api.nvim_buf_is_valid(bufnr) then
      anchors[bufnr] = nil
    end
  end

  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(bufnr) then
      draw(bufnr, review)
    end
  end
end

---Remove the rendered comments from every buffer
---@return nil
function M.clear_all()
  watch(false)

  for bufnr, _ in pairs(anchors) do
    M.clear(bufnr)
  end
  anchors = {}
end

---The pending comment rendered against a line, tracked to wherever the line has moved to
---@param bufnr number
---@param line number A 1-indexed line number
---@return { comment: CodeCompanion.CodeReview.Comment, index: number }|nil
function M.comment_at(bufnr, line)
  local placed = anchors[bufnr]
  if not placed then
    return
  end

  local review = pending_comments()
  for id, index in pairs(placed) do
    local position = api.nvim_buf_get_extmark_by_id(bufnr, CONSTANTS.NAMESPACE, id, {})
    if position[1] and position[1] + 1 == line and review.comments[index] then
      return { comment = review.comments[index], index = index }
    end
  end
end

return M
