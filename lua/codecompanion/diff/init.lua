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

      It works by computing line-level diffs between two versions of a text,
      then further refining changed lines with word-level diffs. For any
      text from an inline request, a separate diff is carried out.

      This code is licensed under the Apache-2.0 License.
-------------------------------------------------------------------------------
    Attribution:
      If you use or distribute this code, please credit:
      Oli Morris (https://github.com/olimorris)
===============================================================================
--]]

local diff_utils = require("codecompanion.diff.utils")
local utils = require("codecompanion.utils")

local api = vim.api

local M = {}

---@type vim.text.diff.Opts
local CONSTANTS = {
  DIFF_LINE_OPTS = {
    algorithm = "patience",
    ctxlen = 0,
    indent_heuristic = true,
    interhunkctxlen = 0,
    linematch = 10,
    result_type = "indices",
  },

  DIFF_WORD_OPTS = {
    algorithm = "histogram",
    result_type = "indices",
  },
}

---@diagnostic disable-next-line: deprecated
local diff_fn = vim.text.diff or vim.diff

---@alias CodeCompanion.Text [string, string|string[]][]

---@class CC.DiffText
---@field text string
---@field lines string[]
---@field virt_lines? CodeCompanion.Text[]

---@alias CodeCompanion.Pos {[1]:number, [2]:number}

---@class CC.Diff
---@field bufnr number
---@field ft string
---@field hunks CodeCompanion.diff.Hunk[]
---@field range { from: CodeCompanion.Pos, to: CodeCompanion.Pos }
---@field from CC.DiffText
---@field to CC.DiffText
---@field namespace number
---@field should_offset boolean
---@field marker_add? string
---@field marker_delete? string

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

---Diff two strings as arrays of lines
---@param a string[]
---@param b string[]
---@param opts? vim.text.diff.Opts
---@return number[][]
function M._diff(a, b, opts)
  opts = opts or CONSTANTS.DIFF_LINE_OPTS
  local txt_a = table.concat(a, "\n")
  local txt_b = table.concat(b, "\n")

  return diff_fn(txt_a, txt_b, opts)
end

---Check if any hunk starts at row 0 and has deletions. This causes a problem
---because virtual lines that need to be rendered above row 0 have no space
---to do so. We workaround this by offsetting the extmarks by 1.
---@param diff CC.Diff
---@return boolean
local function _should_offset(diff)
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

---Process diff hunks to create extmarks for visualization
---@param diff CC.Diff
---@return CC.Diff
function M._diff_lines(diff)
  local hunks = M._diff(diff.from.lines, diff.to.lines, CONSTANTS.DIFF_LINE_OPTS)

  local dels = {} ---@type table<number, {hunk: CodeCompanion.diff.Hunk}>
  local adds = {} ---@type table<number, {hunk: CodeCompanion.diff.Hunk, old_idx: number, new_idx: number, virt_lines: CodeCompanion.Text[]}>

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
      -- Deletions: highlight the lines being deleted
      for l = 0, ac - 1 do
        dels[row + l] = { hunk = h }
      end
    end
    if bc > 0 then
      -- Additions: prepare virtual lines to show below
      local virt_lines = vim.list_slice(diff.to.virt_lines, bi, bi + bc - 1)
      for l = 0, bc - 1 do
        adds[row + l] = { hunk = h, old_idx = ai + l, new_idx = bi + l, virt_lines = virt_lines }
      end
    end
  end

  -- Apply line highlighting for deletions
  for row, data in pairs(dels) do
    local extmark = {
      row = row,
      col = 0,
      line_hl_group = "CodeCompanionDiffDelete",
    }

    -- Add marker for deletions if provided
    if diff.marker_delete then
      extmark.sign_text = diff.marker_delete
      extmark.sign_hl_group = "CodeCompanionDiffDelete"
    end

    table.insert(data.hunk.extmarks, extmark)
  end

  -- Apply virtual lines for additions
  for row, data in pairs(adds) do
    if data.hunk.kind == "change" then
      M._diff_words(diff, row, data)
    end

    -- Only add virtual lines once per hunk at the first addition row
    if row == data.hunk.pos[1] then
      -- For change hunks, position additions after all deletions
      local virt_line_row = row
      if data.hunk.kind == "change" and data.hunk.cover > 0 then
        virt_line_row = data.hunk.pos[1] + data.hunk.cover - 1
      end

      local virt_lines = diff_utils.extend_vl(data.virt_lines, "CodeCompanionDiffAdd")

      -- Add marker to each virtual line if provided
      if diff.marker_add then
        virt_lines = diff_utils.prepend_marker(virt_lines, diff.marker_add, "CodeCompanionDiffAdd")
      end

      table.insert(data.hunk.extmarks, {
        row = virt_line_row,
        col = 0,
        virt_lines = virt_lines,
      })
    end
  end

  return diff
end

---Perform word-level diff on changed lines
---@param diff CC.Diff
---@param row number The row number in the buffer
---@param data { hunk: CodeCompanion.diff.Hunk, old_idx: number, new_idx: number }
function M._diff_words(diff, row, data)
  local old_line = diff.from.lines[data.old_idx] or ""
  local new_line = diff.to.lines[data.new_idx] or ""

  if old_line == "" or new_line == "" then
    return
  end

  local old_words = diff_utils.split_words(old_line)
  local new_words = diff_utils.split_words(new_line)

  -- Extract just the word text for diffing
  local old_text = table.concat(
    vim.tbl_map(function(w)
      return w.word
    end, old_words),
    "\n"
  )
  local new_text = table.concat(
    vim.tbl_map(function(w)
      return w.word
    end, new_words),
    "\n"
  )

  local hunks = diff_fn(old_text, new_text, CONSTANTS.DIFF_WORD_OPTS)

  for _, hunk in ipairs(hunks) do
    local _, _, bi, bc = unpack(hunk)

    -- Only highlight additions/changes in the new line
    if bc > 0 then
      local start_word_idx = bi
      local end_word_idx = bi + bc - 1

      if new_words[start_word_idx] and new_words[end_word_idx] then
        local start_col = new_words[start_word_idx].start_col
        local end_col = new_words[end_word_idx].end_col

        table.insert(data.hunk.extmarks, {
          row = row,
          col = start_col,
          end_col = end_col,
          hl_group = "CodeCompanionDiffChange",
        })
      end
    end
  end
end

---Create a diff between two sets of lines
---@param args {bufnr: number, from_lines: string[], to_lines: string[], ft?: string, marker_add?: string, marker_delete?: string}
---@return CC.Diff
function M.create(args)
  local from_text = table.concat(args.from_lines, "\n")
  local to_text = table.concat(args.to_lines, "\n")

  local diff = M._diff_lines(
    ---@type CC.Diff
    {
      bufnr = args.bufnr,
      ft = args.ft,
      hunks = {},
      range = { from = { 0, 0 }, to = { #args.from_lines - 1, 0 } },
      from = {
        lines = args.from_lines,
        text = from_text,
      },
      to = {
        lines = args.to_lines,
        text = to_text,
        virt_lines = diff_utils.create_vl(to_text, {
          ft = args.ft,
          bg = "CodeCompanionDiffAdd",
        }),
      },
      namespace = api.nvim_create_namespace("codecompanion_diff"),
      should_offset = false,
      marker_add = args.marker_add,
      marker_delete = args.marker_delete,
    }
  )
  diff.should_offset = _should_offset(diff)

  return diff
end

return M
