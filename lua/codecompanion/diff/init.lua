--[[
===============================================================================
    File:       codecompanion/diff.lua
    Author:     Oli Morris
-------------------------------------------------------------------------------
    Description:
      This module implements a simple inline diff utility for CodeCompanion.
      It's primary purpose is to enable developers to rapidly visualize
      the impact of edits from LLMs and Agents on their codebase.

      It is heavily inspired by the awesome work in sidekick.nvim and Zed.

      This code is licensed under the Apache-2.0 License.
-------------------------------------------------------------------------------
    Attribution:
      If you use or distribute this code, please credit:
      Oli Morris (https://github.com/olimorris)
===============================================================================
--]]

local diff_utils = require("codecompanion.diff.utils")

local M = {}

---@type vim.text.diff.Opts
local DIFF_OPTS = {
  algorithm = "patience",
  ctxlen = 0,
  indent_heuristic = true,
  interhunkctxlen = 0,
  linematch = 10,
  result_type = "indices",
}

---@alias CodeCompanion.Text [string, string|string[]][]

---@class CC.DiffText
---@field text string
---@field lines string[]
---@field virt_lines CodeCompanion.Text[]

---@alias CodeCompanion.Pos {[1]:number, [2]:number}

---@class CC.Diff
---@field bufnr number
---@field hunks CodeCompanion.diff.Hunk[]
---@field range { from: CodeCompanion.Pos, to: CodeCompanion.Pos }
---@field from CC.DiffText
---@field to CC.DiffText
---@field namespace number
---@field should_offset boolean

---@class CodeCompanion.diff.Hunk
---@field kind "add"|"delete"|"change"
---@field pos CodeCompanion.Pos Starting position of the hunk in the "from" text
---@field cover number Number of lines covered in the "from" text
---@field extmarks CodeCompanion.diff.Extmark[]

---@class CodeCompanion.diff.Extmark
---@field row number
---@field col number
---@field end_col? number
---@field end_row? number  -- Added for line range highlights
---@field hl_group? string
---@field line_hl_group? string
---@field hl_eol? boolean
---@field virt_text? [string, string|string[]][]
---@field virt_text_win_col? number
---@field virt_lines? CodeCompanion.Text[]
---@field virt_lines_above? boolean

---Diff two strings using vim.text.diff
---@param a string[]
---@param b string[]
---@param opts? vim.text.diff.Opts
---@return number[][]
function M._diff(a, b, opts)
  opts = opts or DIFF_OPTS
  local txt_a = table.concat(a, "\n")
  local txt_b = table.concat(b, "\n")
  return vim.text.diff(txt_a, txt_b, opts)
end

---Check if we need to offset for row 0 deletions and adjust positions
---@param diff CC.Diff
---@return boolean needs_offset
local function _should_offset(diff)
  -- Check if any hunk starts at row 0 with deletions
  -- This is a problem because virtual lines with virt_lines_above=true at row 0
  -- don't render (there's nothing "above" row 0 in a buffer)
  local needs_offset = false
  for _, hunk in ipairs(diff.hunks) do
    if hunk.pos[1] == 0 and hunk.cover > 0 then
      needs_offset = true
      break
    end
  end

  if not needs_offset then
    return false
  end

  -- Shift all positions down by 1 to account for the blank line we'll insert
  for _, hunk in ipairs(diff.hunks) do
    hunk.pos[1] = hunk.pos[1] + 1
    for _, extmark in ipairs(hunk.extmarks) do
      extmark.row = extmark.row + 1
      if extmark.end_row then
        extmark.end_row = extmark.end_row + 1
      end
    end
  end

  return true
end

---Process hunks to create extmarks for visualization
---@param diff CC.Diff
function M.diff_lines(diff)
  local hunks = M._diff(diff.from.lines, diff.to.lines, DIFF_OPTS)
  local dels = {} ---@type table<number, {hunk: CodeCompanion.diff.Hunk}>
  local adds = {} ---@type table<number, {hunk: CodeCompanion.diff.Hunk, virt_lines: CodeCompanion.Text[]}>

  local width = 0
  for _, hunk in ipairs(hunks) do
    local ai, ac, bi, bc = unpack(hunk)

    local row = math.max(diff.range.from[1] + ai - 1, 0)
    ---@type CodeCompanion.diff.Hunk
    local h = {
      kind = ac > 0 and bc > 0 and "change" or ac > 0 and "delete" or "add",
      pos = { row, 0 },
      cover = ac,
      extmarks = {},
    }
    table.insert(diff.hunks, h)
    if ac > 0 then
      for l = 0, ac - 1 do
        dels[row + l] = { hunk = h }
        width = math.max(width, diff_utils.get_width(diff.from.lines[ai + l] or ""))
      end
    end
    if bc > 0 then
      local virt_lines = vim.list_slice(diff.to.virt_lines, bi, bi + bc - 1)
      width = math.max(width, diff_utils.lines_width(virt_lines))
      adds[row + (ac > 0 and ac - 1 or 0)] = { hunk = h, virt_lines = virt_lines }
    end
  end

  for row, info in pairs(dels) do
    table.insert(info.hunk.extmarks, {
      row = row,
      col = 0,
      virt_text_win_col = width + 1,
      virt_text = { { string.rep(" ", vim.o.columns), "CodeCompanionDiffContext" } },
      line_hl_group = "CodeCompanionDiffDelete",
    })
  end

  for row, info in pairs(adds) do
    table.insert(info.hunk.extmarks, {
      row = row,
      col = 0,
      hl_eol = true,
      virt_lines = diff_utils.highlight_block(info.virt_lines, {
        leading = "CodeCompanionDiffContext",
        trailing = "CodeCompanionDiffContext",
        block = "CodeCompanionDiffAdd",
        width = width + 1,
      }),
    })
  end
end

---Create a diff between two sets of lines
---@param args {bufnr: number, from_lines: string[], to_lines: string[], ft?: string}
---@return CC.Diff
function M.create(args)
  local from_text = table.concat(args.from_lines, "\n")
  local to_text = table.concat(args.to_lines, "\n")

  ---@type CC.Diff
  local diff = {
    bufnr = args.bufnr,
    hunks = {},
    range = { from = { 0, #args.from_lines - 1 }, to = { 0, #args.to_lines - 1 } },
    from = {
      lines = args.from_lines,
      text = from_text,
      virt_lines = diff_utils.get_virtual_lines(from_text, {
        ft = args.ft,
      }),
    },
    to = {
      lines = args.to_lines,
      text = to_text,
      virt_lines = diff_utils.get_virtual_lines(to_text, {
        ft = args.ft,
        bg = "CodeCompanionDiffAdd",
      }),
    },
    namespace = vim.api.nvim_create_namespace("codecompanion_diff"),
    should_offset = false,
  }

  M.diff_lines(diff)

  -- Solution: Insert a blank line at row 0, shifting all content down by 1
  -- Then adjust all extmark positions to account for this shift
  -- This allows deletion virtual lines to appear "above" the first line of actual content
  diff.should_offset = _should_offset(diff)

  return diff
end

---Clear diff extmarks from buffer
---@param diff CC.Diff
function M.clear(diff)
  vim.api.nvim_buf_clear_namespace(diff.bufnr, diff.namespace, 0, -1)
end

---Apply diff extmarks to buffer
---@param diff CC.Diff
function M.apply(diff)
  -- Ensure buffer has content
  local line_count = vim.api.nvim_buf_line_count(diff.bufnr)
  if line_count == 0 then
    vim.notify("Cannot apply diff to empty buffer", vim.log.levels.ERROR)
    return
  end

  -- Insert blank line at top if needed for row 0 deletions
  -- This creates visual space for deletion virtual lines to appear "above" first line
  if diff.should_offset then
    vim.api.nvim_buf_set_lines(diff.bufnr, 0, 0, false, { "" })
  end

  for _, hunk in ipairs(diff.hunks) do
    for _, extmark in ipairs(hunk.extmarks) do
      local opts = {}
      for k, v in pairs(extmark) do
        if k ~= "row" and k ~= "col" then
          opts[k] = v
        end
      end

      pcall(vim.api.nvim_buf_set_extmark, diff.bufnr, diff.namespace, extmark.row, extmark.col, opts)
    end
  end
end

return M
