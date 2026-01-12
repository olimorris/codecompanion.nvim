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
---@field ns number The namespace
---@field marker_add? string The marker to signify a line addition
---@field marker_delete? string The marker to signify a line deletion

---@class CodeCompanion.diff.Hunk
---@field kind "add"|"delete"|"change"
---@field pos CodeCompanion.Pos Starting position of the hunk in the "from" text
---@field cover number Number of lines covered in the "from" text
---@field extmarks CodeCompanion.diff.Extmark[]
---@field word_ranges? { line_idx: number, start_col: number, end_col: number }[]

---@class CodeCompanion.diff.Extmark
---@field row number
---@field col number
---@field type? "addition"|"deletion" Type of extmark for styling
---@field end_row? number
---@field virt_lines? CodeCompanion.Text[]

---Diff two strings as arrays of lines
---@param a string[]
---@param b string[]
---@param opts? vim.text.diff.Opts
---@return number[][]
function M._diff(a, b, opts)
  opts = opts or CONSTANTS.DIFF_LINE_OPTS
  local txt_a = table.concat(a, "\n")
  local txt_b = table.concat(b, "\n")

  local result = diff_fn(txt_a, txt_b, opts)

  if type(result) == "table" then
    return result
  end

  return {}
end

---Process diff hunks to create extmarks for visualization
---@param diff CC.Diff
---@return CC.Diff
function M._diff_lines(diff)
  local hunks = M._diff(diff.from.lines, diff.to.lines, CONSTANTS.DIFF_LINE_OPTS)

  local dels = {} ---@type table<number, {hunk: CodeCompanion.diff.Hunk}>
  local adds = {} ---@type table<number, {hunk: CodeCompanion.diff.Hunk, old_idx: number, new_idx: number, virt_lines: CodeCompanion.Text[], first_line_idx: number}>

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
        adds[row + l] = { hunk = h, old_idx = ai + l, new_idx = bi + l, virt_lines = virt_lines, first_line_idx = bi }
      end
    end
  end

  -- Create deletion extmarks (without styling)
  for row, data in pairs(dels) do
    table.insert(data.hunk.extmarks, {
      row = row,
      col = 0,
      type = "deletion",
    })
  end

  -- Collect word-level changes for all changed lines
  local word_ranges_by_hunk = {} ---@type table<CodeCompanion.diff.Hunk, { line_idx: number, start_col: number, end_col: number }[]>
  for row, data in pairs(adds) do
    if data.hunk.kind == "change" then
      local word_ranges = M._diff_words(diff, row, data)
      if word_ranges then
        word_ranges_by_hunk[data.hunk] = word_ranges_by_hunk[data.hunk] or {}
        vim.list_extend(word_ranges_by_hunk[data.hunk], word_ranges)
      end
    end
  end

  -- Store word ranges in hunks for later styling
  for hunk, ranges in pairs(word_ranges_by_hunk) do
    hunk.word_ranges = ranges
  end

  -- Create addition extmarks (without styling)
  for row, data in pairs(adds) do
    if row == data.hunk.pos[1] then
      local virt_line_row = row
      if data.hunk.kind == "change" and data.hunk.cover > 0 then
        virt_line_row = data.hunk.pos[1] + data.hunk.cover - 1
      end

      table.insert(data.hunk.extmarks, {
        row = virt_line_row,
        col = 0,
        type = "addition",
        virt_lines = data.virt_lines,
      })
    end
  end

  return diff
end

---Perform word-level diff on changed lines
---@param diff CC.Diff
---@param row number The row number in the buffer
---@param data { hunk: CodeCompanion.diff.Hunk, old_idx: number, new_idx: number, first_line_idx: number }
---@return { line_idx: number, start_col: number, end_col: number }[]?
function M._diff_words(diff, row, data)
  local old_line = diff.from.lines[data.old_idx] or ""
  local new_line = diff.to.lines[data.new_idx] or ""

  if old_line == "" or new_line == "" then
    return nil
  end

  local old_words = diff_utils.split_words(old_line)
  local new_words = diff_utils.split_words(new_line)

  -- Convert words to text for diffing
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

  local result = diff_fn(old_text, new_text, CONSTANTS.DIFF_WORD_OPTS)
  if type(result) ~= "table" then
    return nil
  end

  local word_ranges = {}
  for _, hunk in ipairs(result) do
    local _, _, bi, bc = unpack(hunk)

    -- Track additions for virtual lines
    if bc > 0 and new_words[bi] and new_words[bi + bc - 1] then
      table.insert(word_ranges, {
        line_idx = data.new_idx - data.first_line_idx + 1,
        start_col = new_words[bi].start_col,
        end_col = new_words[bi + bc - 1].end_col,
      })
    end
  end

  return #word_ranges > 0 and word_ranges or nil
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
      ns = api.nvim_create_namespace("codecompanion_diff"),
      marker_add = args.marker_add,
      marker_delete = args.marker_delete,
    }
  )

  return diff
end

return M
