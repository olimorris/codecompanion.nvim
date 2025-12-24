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

---@class CC.Diff
---@field bufnr number
---@field hunks CodeCompanion.diff.Hunk[]
---@field from CC.DiffText
---@field to CC.DiffText
---@field namespace number
---@field has_row_0_offset boolean Whether a blank line was inserted at row 0

---@class CodeCompanion.diff.Hunk
---@field kind "add"|"delete"|"change"
---@field pos [number, number] Position as [row, col]
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
---@return integer[][]
function M._diff(a, b, opts)
  opts = opts or DIFF_OPTS
  local txt_a = table.concat(a, "\n")
  local txt_b = table.concat(b, "\n")
  return vim.text.diff(txt_a, txt_b, opts)
end

---Placeholder for treesitter virtual lines
---TODO: Implement proper treesitter highlighting
---@param text string
---@param opts? {ft?: string, bg?: string}
---@return CodeCompanion.Text[]
local function get_virtual_lines(text, opts)
  local lines = vim.split(text, "\n", { plain = true })
  local virt_lines = {}
  for _, line in ipairs(lines) do
    table.insert(virt_lines, { { line, opts and opts.bg } })
  end
  return virt_lines
end

---Placeholder for treesitter block highlighting
---TODO: Implement proper block highlighting with leading/trailing context
---@param virt_lines CodeCompanion.Text[]
---@param opts? {leading?: string, trailing?: string, block?: string, width?: number}
---@return CodeCompanion.Text[]
---@diagnostic disable-next-line: unused-local
local function highlight_block(virt_lines, opts)
  -- For now, just return the lines as-is
  -- The highlight groups are already applied in the virt_lines structure
  return virt_lines
end

---Calculate text width (placeholder)
---TODO: Use proper strwidth calculation
---@param text string
---@return number
local function text_width(text)
  return #text
end

---Calculate width of virtual lines
---@param virt_lines CodeCompanion.Text[]
---@return number
local function lines_width(virt_lines)
  local max_width = 0
  for _, line in ipairs(virt_lines) do
    local width = 0
    for _, chunk in ipairs(line) do
      width = width + text_width(chunk[1])
    end
    max_width = math.max(max_width, width)
  end
  return max_width
end

---Build extmark options from extmark table (filters out row/col)
---@param extmark CodeCompanion.diff.Extmark
---@return table opts
local function build_extmark_opts(extmark)
  local opts = {}
  for k, v in pairs(extmark) do
    if k ~= "row" and k ~= "col" then
      opts[k] = v
    end
  end
  return opts
end

---Check if we need to offset for row 0 deletions and adjust positions
---@param diff CC.Diff
---@return boolean needs_offset
local function apply_row_0_offset(diff)
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
  local width = 0

  for _, hunk in ipairs(hunks) do
    local ai, ac, bi, bc = unpack(hunk)
    -- Use 'bi' (to/after index) for positioning since buffer has "after" content
    local row = bi - 1 -- Convert to 0-indexed

    ---@type CodeCompanion.diff.Hunk
    local h = {
      kind = ac > 0 and bc > 0 and "change" or ac > 0 and "delete" or "add",
      pos = { row, 0 },
      cover = ac,
      extmarks = {},
    }
    table.insert(diff.hunks, h)

    -- Calculate width from deleted lines
    if ac > 0 then
      for l = 0, ac - 1 do
        width = math.max(width, text_width(diff.from.lines[ai + l] or ""))
      end
    end

    -- Calculate width from added lines
    if bc > 0 then
      local virt_lines = vim.list_slice(diff.to.virt_lines, bi, bi + bc - 1)
      width = math.max(width, lines_width(virt_lines))
    end

    -- Create extmark for deletions (all deleted lines in one extmark)
    -- Show above the corresponding "after" lines
    if ac > 0 then
      local del_virt_lines = {}
      for l = 0, ac - 1 do
        local line_idx = ai + l -- 1-indexed for from.lines
        local line_content = diff.from.lines[line_idx] or ""
        table.insert(del_virt_lines, { { line_content, "CodeCompanionDiffDelete" } })
      end

      table.insert(h.extmarks, {
        row = row,
        col = 0,
        virt_lines = del_virt_lines,
        virt_lines_above = true,
      })
    end

    -- For pure additions, show green highlight
    -- For changes/deletions, user can see the changed content vs deletions above
    -- Highlight both additions and changes for now
    if bc > 0 then
      for l = 0, bc - 1 do
        table.insert(h.extmarks, {
          row = row + l,
          col = 0,
          end_row = row + l + 1,
          hl_group = "CodeCompanionDiffAdd",
        })
      end
    end
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
    from = {
      text = from_text,
      lines = args.from_lines,
      virt_lines = get_virtual_lines(from_text, {
        ft = args.ft,
      }),
    },
    to = {
      text = to_text,
      lines = args.to_lines,
      virt_lines = get_virtual_lines(to_text, {
        ft = args.ft,
        bg = "CodeCompanionDiffAdd",
      }),
    },
    namespace = vim.api.nvim_create_namespace("codecompanion_diff"),
    has_row_0_offset = false, -- Track if we added offset
  }

  M.diff_lines(diff)

  -- Solution: Insert a blank line at row 0, shifting all content down by 1
  -- Then adjust all extmark positions to account for this shift
  -- This allows deletion virtual lines to appear "above" the first line of actual content
  diff.has_row_0_offset = apply_row_0_offset(diff)

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
  if diff.has_row_0_offset then
    vim.api.nvim_buf_set_lines(diff.bufnr, 0, 0, false, { "" })
  end

  for _, hunk in ipairs(diff.hunks) do
    for _, extmark in ipairs(hunk.extmarks) do
      local row = extmark.row
      local col = extmark.col
      local opts = build_extmark_opts(extmark)

      local ok, err = pcall(vim.api.nvim_buf_set_extmark, diff.bufnr, diff.namespace, row, col, opts)
      if not ok then
        vim.notify(string.format("Failed to set extmark at row %d: %s", row, err), vim.log.levels.ERROR)
      end
    end
  end
end

return M
