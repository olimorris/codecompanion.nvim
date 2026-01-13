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

local M = {}

---@type vim.text.diff.Opts
local CONSTANTS = {
  DIFF_LINE_OPTS = {
    algorithm = "histogram",
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

---@alias CodeCompanion.Pos {[1]:number, [2]:number}

---@class CC.Diff
---@field bufnr number
---@field ft string
---@field hunks CodeCompanion.diff.Hunk[]
---@field from CC.DiffText
---@field to CC.DiffText
---@field merged { lines: string[], highlights: { row: number, type: "addition"|"deletion"|"change", word_hl?: { col: number, end_col: number }[] }[] } Merged lines for display
---@field marker_add? string The marker to signify a line addition
---@field marker_delete? string The marker to signify a line deletion

---@class CodeCompanion.diff.Hunk
---@field extmarks CodeCompanion.diff.Extmark[]
---@field kind "add"|"delete"|"change"
---@field pos CodeCompanion.Pos Starting position of the hunk in the "from" text

---@class CodeCompanion.diff.Extmark
---@field row number
---@field col number
---@field end_row? number
---@field type? "addition"|"deletion" Type of extmark for styling

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

---Add a highlight entry with optional word-level ranges
---@param highlights table[] The highlights table to append to
---@param merged_row number The row number in merged view
---@param type "addition"|"deletion" The type of highlight
---@param word_ranges? { col: number, end_col: number }[] Optional word-level highlight ranges
local function add_highlight(highlights, merged_row, type, word_ranges)
  local hl_entry = { row = merged_row, type = type }
  if word_ranges then
    hl_entry.word_hl = word_ranges
  end
  table.insert(highlights, hl_entry)
end

---Add an extmark entry to a hunk
---@param hunk CodeCompanion.diff.Hunk The hunk to add the extmark to
---@param merged_row number The row number in merged view (1-indexed)
---@param type "addition"|"deletion" The type of extmark
local function add_extmark(hunk, merged_row, type)
  table.insert(hunk.extmarks, { row = merged_row - 1, col = 0, type = type })
end

---Process diff hunks to create merged lines for display
---@param diff CC.Diff
---@return CC.Diff
function M._diff_lines(diff)
  local hunks = M._diff(diff.from.lines, diff.to.lines, CONSTANTS.DIFF_LINE_OPTS)

  -- Instead of using virtual text, we create a merged view of the lines and we
  -- build out the highlights for the possible hunk types
  local merged_lines = {} ---@type string[]
  local highlights = {} ---@type { row: number, type: "addition"|"deletion"|"change", word_hl?: { col: number, end_col: number }[] }[]

  local from_pos = 1
  local merged_row = 0

  for _, hunk in ipairs(hunks) do
    local from_start, from_count, to_start, to_count = unpack(hunk)

    local kind = from_count > 0 and to_count > 0 and "change" or from_count > 0 and "delete" or "add"

    -- Add unchanged lines before this hunk
    -- For pure additions (from_count=0), from_start is the line AFTER which to insert, so include it
    -- For deletions/changes, from_start is the first line to delete, so stop before it
    local stop_at = kind == "add" and from_start or from_start - 1
    while from_pos <= stop_at do
      merged_row = merged_row + 1
      table.insert(merged_lines, diff.from.lines[from_pos])
      from_pos = from_pos + 1
    end

    ---@type CodeCompanion.diff.Hunk
    local h = {
      extmarks = {},
      kind = kind,
      pos = { merged_row, 0 },
    }
    table.insert(diff.hunks, h)

    -- For changes, compute word-level diffs
    local word_diff_results = {}
    if kind == "change" then
      for i = 0, math.min(from_count, to_count) - 1 do
        local old_line = diff.from.lines[from_start + i] or ""
        local new_line = diff.to.lines[to_start + i] or ""
        local del_ranges, add_ranges = M._diff_words(old_line, new_line)
        word_diff_results[i] = { del_ranges = del_ranges, add_ranges = add_ranges }
      end
    end

    -- Add deletion lines
    for i = 0, from_count - 1 do
      merged_row = merged_row + 1
      add_extmark(h, merged_row, "deletion")
      table.insert(merged_lines, diff.from.lines[from_start + i])

      local word_ranges = word_diff_results[i] and word_diff_results[i].del_ranges or nil
      add_highlight(highlights, merged_row, "deletion", word_ranges)
    end
    from_pos = from_pos + from_count

    -- Add addition lines
    for i = 0, to_count - 1 do
      merged_row = merged_row + 1
      add_extmark(h, merged_row, "addition")
      table.insert(merged_lines, diff.to.lines[to_start + i])

      local word_ranges = word_diff_results[i] and word_diff_results[i].add_ranges or nil
      add_highlight(highlights, merged_row, "addition", word_ranges)
    end
  end

  -- Add remaining unchanged lines
  while from_pos <= #diff.from.lines do
    merged_row = merged_row + 1
    table.insert(merged_lines, diff.from.lines[from_pos])
    from_pos = from_pos + 1
  end

  diff.merged = {
    lines = merged_lines,
    highlights = highlights,
  }

  return diff
end

---Perform word-level diff between two lines
---@param old_line string
---@param new_line string
---@return { col: number, end_col: number }[]? del_ranges
---@return { col: number, end_col: number }[]? add_ranges
function M._diff_words(old_line, new_line)
  if old_line == "" or new_line == "" then
    return nil, nil
  end

  local old_words = diff_utils.split_words(old_line)
  local new_words = diff_utils.split_words(new_line)

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
    return nil, nil
  end

  local del_ranges = {}
  local add_ranges = {}

  for _, hunk in ipairs(result) do
    local from_start, from_count, to_start, to_count = unpack(hunk)

    if from_count > 0 and old_words[from_start] and old_words[from_start + from_count - 1] then
      table.insert(del_ranges, {
        col = old_words[from_start].start_col,
        end_col = old_words[from_start + from_count - 1].end_col,
      })
    end

    if to_count > 0 and new_words[to_start] and new_words[to_start + to_count - 1] then
      table.insert(add_ranges, {
        col = new_words[to_start].start_col,
        end_col = new_words[to_start + to_count - 1].end_col,
      })
    end
  end

  return #del_ranges > 0 and del_ranges or nil, #add_ranges > 0 and add_ranges or nil
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
      from = {
        lines = args.from_lines,
        text = from_text,
      },
      to = {
        lines = args.to_lines,
        text = to_text,
      },
      merged = { lines = {}, highlights = {} },
      marker_add = args.marker_add,
      marker_delete = args.marker_delete,
    }
  )

  return diff
end

return M
