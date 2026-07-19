local config = require("codecompanion.config")
local input = require("codecompanion.interactions.shared.input")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local api = vim.api
local fmt = string.format

---@class CodeCompanion.Annotation
---@field comment string
---@field code string
---@field filetype string
---@field path string
---@field start_line number
---@field end_line number

local store = {} ---@type CodeCompanion.Annotation[]

local M = {}

---Add an annotation to the store
---@param annotation CodeCompanion.Annotation
---@return nil
function M.add(annotation)
  table.insert(store, annotation)
end

---Return all pending annotations
---@return CodeCompanion.Annotation[]
function M.all()
  return store
end

---Return the number of pending annotations
---@return number
function M.count()
  return #store
end

---Remove all pending annotations
---@return nil
function M.clear()
  store = {}
end

---Snapshot the code and location the user is annotating
---@param bufnr number
---@param args? table
---@return { code: string, filetype: string, path: string, start_line: number, end_line: number }
local function snapshot(bufnr, args)
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

---Annotate the current line or visual selection with a comment
---@param args? table
---@return nil
function M.create(args)
  if not config.can_send_code() then
    return log:warn("Sending of code has been disabled")
  end

  local annotated = snapshot(api.nvim_get_current_buf(), args)

  input.open({
    title = " Annotate ",
    on_submit = function(comment)
      M.add(vim.tbl_extend("force", annotated, { comment = comment }))
      utils.notify(fmt("Annotation added (%d pending)", M.count()))
    end,
  })
end

return M
