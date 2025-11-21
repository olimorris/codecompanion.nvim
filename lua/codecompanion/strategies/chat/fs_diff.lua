---@class CodeCompanion.FSDiff
-- Two-window diff viewer for fs_monitor changes
-- Top: File list (files only)
-- Bottom: Summary stats (30% height of top)
-- Right: Diff preview with syntax highlighting

local api = vim.api
local diff_utils = require("codecompanion.providers.diff.utils")
local log = require("codecompanion.utils.log")
local set_option = vim.api.nvim_set_option_value

local M = {}

-- Blend two hex colors
---@param fg string foreground color
---@param bg string background color
---@param alpha number number between 0 and 1. 0 results in bg, 1 results in fg
local function blend(fg, bg, alpha)
  local bg_rgb = { tonumber(bg:sub(2, 3), 16), tonumber(bg:sub(4, 5), 16), tonumber(bg:sub(6, 7), 16) }
  local fg_rgb = { tonumber(fg:sub(2, 3), 16), tonumber(fg:sub(4, 5), 16), tonumber(fg:sub(6, 7), 16) }
  local blend_channel = function(i)
    local ret = (alpha * fg_rgb[i] + ((1 - alpha) * bg_rgb[i]))
    return math.floor(math.min(math.max(0, ret), 255) + 0.5)
  end
  return string.format("#%02x%02x%02x", blend_channel(1), blend_channel(2), blend_channel(3))
end

-- Get normal background color
local function get_normal_bg()
  local normal_hl = api.nvim_get_hl(0, { name = "Normal" })
  if normal_hl.bg then
    return string.format("#%06x", normal_hl.bg)
  end
  return vim.o.background == "dark" and "#1e1e2e" or "#f5f5f5"
end

-- Highlight groups
local function setup_highlights()
  local normal_bg = get_normal_bg()

  -- Base colors for diff types
  local add_fg = "#a6e3a1"
  local delete_fg = "#f38ba8"
  local change_fg = "#f9e2af"
  local context_fg = "#6c7086"

  local hl_groups = {
    FSDiffAdd = { link = "DiffAdd", default = true },
    FSDiffDelete = { link = "DiffDelete", default = true },
    FSDiffChange = { link = "DiffChange", default = true },
    FSDiffText = { link = "DiffText", default = true },
    FSDiffContext = { link = "DiffChange", default = true },
    FSDiffAddLineNr = { fg = add_fg, bg = blend(add_fg, normal_bg, 0.1), default = true },
    FSDiffDeleteLineNr = { fg = delete_fg, bg = blend(delete_fg, normal_bg, 0.1), default = true },
    FSDiffChangeLineNr = { fg = change_fg, bg = blend(change_fg, normal_bg, 0.1), default = true },
    FSDiffContextLineNr = { fg = context_fg, bg = blend(context_fg, normal_bg, 0.1), default = true },
    FSDiffHeader = { link = "Title", default = true },
    FSDiffSummary = { link = "Comment", default = true },
  }

  for name, opts in pairs(hl_groups) do
    api.nvim_set_hl(0, name, opts)
  end
end

-- Calculate window geometry (3 windows: files top, summary bottom, preview right)
local function calculate_geometry()
  local cols = vim.o.columns
  local lines = math.max(4, vim.o.lines - vim.o.cmdheight - 2)
  local gap = 2

  local right_w = math.max(40, math.floor(cols * 0.65))
  local left_w = math.max(20, math.floor(cols * 0.30))

  local total = left_w + gap + right_w

  if total > cols then
    local scale = cols / total
    left_w = math.max(15, math.floor(left_w * scale))
    right_w = math.max(30, math.floor(right_w * scale))
    total = left_w + gap + right_w
  end

  local height = math.max(10, math.floor(lines * 0.80))
  local row = math.max(0, math.floor((vim.o.lines - height) / 2))
  local col = math.max(0, math.floor((cols - total) / 2))

  -- Split left side: files and checkpoints should total to preview height
  local checkpoints_h = math.max(5, math.floor(height * 0.30))
  local left_gap = 1
  local files_h = math.max(3, height - checkpoints_h - left_gap)

  return {
    left_w = left_w,
    right_w = right_w,
    height = height,
    row = row,
    left_col = col,
    right_col = col + left_w + gap,
    gap = gap,
    files_h = files_h,
    checkpoints_h = checkpoints_h,
    checkpoints_row = row + files_h + left_gap,
  }
end

-- Determine the net operation for a file across all changes in a session
---@param file_changes CodeCompanion.FSMonitor.Change[]
---@return "created"|"modified"|"deleted"
local function determine_net_operation(file_changes)
  local has_created = false
  local has_deleted = false

  for _, change in ipairs(file_changes) do
    if change.kind == "created" then
      has_created = true
    elseif change.kind == "deleted" then
      has_deleted = true
    end
  end

  -- Deleted wins (file ended up deleted)
  if has_deleted then
    return "deleted"
  end

  -- If created in this session, it's still "created" even if modified later
  if has_created then
    return "created"
  end

  -- Otherwise it's a modification to an existing file
  return "modified"
end

-- Generate summary stats from changes
---@param changes CodeCompanion.FSMonitor.Change[]
---@return table summary
local function generate_summary(changes)
  local summary = {
    total = #changes,
    created = 0,
    modified = 0,
    deleted = 0,
    files = {},
    by_file = {},
  }

  for _, change in ipairs(changes) do
    if change.kind == "created" then
      summary.created = summary.created + 1
    elseif change.kind == "modified" then
      summary.modified = summary.modified + 1
    elseif change.kind == "deleted" then
      summary.deleted = summary.deleted + 1
    end

    if not summary.by_file[change.path] then
      summary.by_file[change.path] = {
        path = change.path,
        changes = {},
        net_operation = nil, -- Computed after all changes collected
        created = 0,
        modified = 0,
        deleted = 0,
      }
      table.insert(summary.files, change.path)
    end

    local file_summary = summary.by_file[change.path]
    table.insert(file_summary.changes, change)
    file_summary[change.kind] = file_summary[change.kind] + 1
  end

  -- Compute net operation for each file
  for _, filepath in ipairs(summary.files) do
    local file_summary = summary.by_file[filepath]
    file_summary.net_operation = determine_net_operation(file_summary.changes)
  end

  return summary
end

-- Format diff lines with extmarks for line numbers, highlights, and signs
---@param buf number
---@param ns number
---@param hunks CodeCompanion.Diff.Utils.DiffHunk[]
---@param old_lines string[]
---@param new_lines string[]
---@return number line_count
local function render_diff(buf, ns, hunks, old_lines, new_lines)
  local lines = {}
  local extmarks = {}
  local sign_text = "▌"

  for hunk_idx, hunk in ipairs(hunks) do
    -- Hunk header
    local header = string.format(
      "@@ -%d,%d +%d,%d @@",
      hunk.original_start,
      hunk.original_count,
      hunk.updated_start,
      hunk.updated_count
    )
    table.insert(lines, header)
    table.insert(extmarks, {
      line = #lines - 1,
      col = 0,
      opts = {
        end_line = #lines,
        hl_group = "FSDiffHeader",
      },
    })

    -- Context before
    for idx, ctx_line in ipairs(hunk.context_before) do
      local line_nr = hunk.original_start - #hunk.context_before + idx - 1
      table.insert(lines, ctx_line)
      local line_nr_text = string.format("%4d  %4d ", line_nr, line_nr)
      table.insert(extmarks, {
        line = #lines - 1,
        col = 0,
        opts = {
          line_hl_group = "FSDiffContext",
          virt_text = { { line_nr_text, "FSDiffContextLineNr" } },
          virt_text_pos = "inline",
          hl_mode = "replace",
          sign_text = sign_text,
          sign_hl_group = "FSDiffContextLineNr",
        },
      })
    end

    -- Removed lines (only show old line number)
    local is_modified_hunk = #hunk.removed_lines > 0 and #hunk.added_lines > 0
    for idx, removed_line in ipairs(hunk.removed_lines) do
      local old_line_nr = hunk.original_start + idx - 1
      table.insert(lines, removed_line)
      local line_nr_text = string.format("%4d       ", old_line_nr)
      local sign_hl = is_modified_hunk and "FSDiffChangeLineNr" or "FSDiffDeleteLineNr"
      table.insert(extmarks, {
        line = #lines - 1,
        col = 0,
        opts = {
          line_hl_group = "FSDiffDelete",
          virt_text = { { line_nr_text, "FSDiffDeleteLineNr" } },
          virt_text_pos = "inline",
          sign_text = sign_text,
          sign_hl_group = sign_hl,
        },
      })
    end

    -- Added lines (only show new line number)
    for idx, added_line in ipairs(hunk.added_lines) do
      local new_line_nr = hunk.updated_start + idx - 1
      table.insert(lines, added_line)
      local line_nr_text = string.format("      %4d ", new_line_nr)
      local sign_hl = is_modified_hunk and "FSDiffChangeLineNr" or "FSDiffAddLineNr"
      table.insert(extmarks, {
        line = #lines - 1,
        col = 0,
        opts = {
          line_hl_group = "FSDiffAdd",
          virt_text = { { line_nr_text, "FSDiffAddLineNr" } },
          virt_text_pos = "inline",
          sign_text = sign_text,
          sign_hl_group = sign_hl,
        },
      })
    end

    -- Context after
    for idx, ctx_line in ipairs(hunk.context_after) do
      local line_nr = hunk.original_start + hunk.original_count + idx - 1
      table.insert(lines, ctx_line)
      local line_nr_text = string.format("%4d  %4d ", line_nr, line_nr)
      table.insert(extmarks, {
        line = #lines - 1,
        col = 0,
        opts = {
          line_hl_group = "FSDiffContext",
          virt_text = { { line_nr_text, "FSDiffContextLineNr" } },
          virt_text_pos = "inline",
          sign_text = sign_text,
          sign_hl_group = "FSDiffContextLineNr",
        },
      })
    end

    -- Separator between hunks
    if hunk_idx < #hunks then
      table.insert(lines, "")
      table.insert(lines, "")
    end
  end

  -- Handle empty diff
  if #lines == 0 then
    table.insert(lines, "")
    table.insert(lines, "No differences detected")
    table.insert(lines, "")
  end

  api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  for _, mark in ipairs(extmarks) do
    pcall(api.nvim_buf_set_extmark, buf, ns, mark.line, mark.col, mark.opts)
  end

  return #lines
end

-- Render file list in files buffer (top left)
---@param buf number
---@param ns number
---@param files string[]
---@param by_file table
---@param selected_idx? number
local function render_file_list(buf, ns, files, by_file, selected_idx)
  local lines = {}
  local extmarks = {}

  for idx, filepath in ipairs(files) do
    local file_info = by_file[filepath]
    local icon = " "

    -- Use net_operation for icon
    if file_info.net_operation == "created" then
      icon = "󰙴 "
    elseif file_info.net_operation == "deleted" then
      icon = "󰧧 "
    elseif file_info.net_operation == "modified" then
      icon = " "
    end

    local prefix = idx == selected_idx and "▶ " or "  "
    local name = vim.fn.fnamemodify(filepath, ":t")
    local dir = vim.fn.fnamemodify(filepath, ":h")
    if dir == "." then
      dir = ""
    else
      dir = dir .. "/"
    end

    local line = string.format("%s%s %s : %s", prefix, icon, name, dir)
    table.insert(lines, line)

    -- Add extmark to highlight the filename
    local name_start = #prefix + #icon + 1
    local name_end = name_start + #name
    table.insert(extmarks, {
      line = #lines - 1,
      col = name_start,
      opts = {
        end_col = name_end,
        hl_group = "Title",
      },
    })
  end

  api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  for _, mark in ipairs(extmarks) do
    pcall(api.nvim_buf_set_extmark, buf, ns, mark.line, mark.col, mark.opts)
  end
end

-- Render checkpoints in checkpoint buffer (bottom left)
---@param buf number
---@param ns number
---@param checkpoints CodeCompanion.FSMonitor.Checkpoint[]
---@param all_changes CodeCompanion.FSMonitor.Change[]
---@param selected_idx? number
local function render_checkpoints(buf, ns, checkpoints, all_changes, selected_idx)
  local lines = {}
  local extmarks = {}

  if #checkpoints == 0 then
    table.insert(lines, "No checkpoints yet")
    table.insert(lines, "")
    table.insert(lines, "Checkpoints are created after")
    table.insert(lines, "each LLM response with changes")
  else
    table.insert(lines, "Checkpoints")
    table.insert(lines, "")

    for idx, cp in ipairs(checkpoints) do
      -- Count changes up to this checkpoint
      local change_count = 0
      for _, change in ipairs(all_changes) do
        if change.timestamp <= cp.timestamp then
          change_count = change_count + 1
        end
      end

      local prefix = idx == selected_idx and "▶ " or "  "
      local icon = " "
      local label = cp.label or string.format("Cycle %d", cp.cycle or idx)

      local line = string.format("%s%s %s - %d changes", prefix, icon, label, change_count)
      table.insert(lines, line)

      -- Highlight the label
      local label_start = #prefix + #icon + 1
      local label_end = label_start + #label
      table.insert(extmarks, {
        line = #lines - 1,
        col = label_start,
        opts = {
          end_col = label_end,
          hl_group = "Title",
        },
      })
    end

    table.insert(lines, "")
    local hint = selected_idx and "Enter: View  r: Reset  ?: Help" or "Enter: View checkpoint  r: Reset  ?: Help"
    table.insert(lines, hint)
  end

  api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  for _, mark in ipairs(extmarks) do
    pcall(api.nvim_buf_set_extmark, buf, ns, mark.line, mark.col, mark.opts)
  end
end

-- Reapply keymaps to right buffer (needed after filetype changes)
local function reapply_right_keymaps(state)
  if not state.right_keymaps or not api.nvim_buf_is_valid(state.right_buf) then
    return
  end

  for _, map in ipairs(state.right_keymaps) do
    local mode, lhs, rhs, desc = unpack(map)
    vim.keymap.set(mode, lhs, rhs, {
      buffer = state.right_buf,
      noremap = true,
      silent = true,
      nowait = true,
      desc = desc,
    })
  end
end

-- Update preview for selected file
---@param state table
---@param idx number
local function update_preview(state, idx)
  local filepath = state.summary.files[idx]
  if not filepath then
    return
  end

  local file_info = state.summary.by_file[filepath]
  if not file_info or #file_info.changes == 0 then
    return
  end

  -- Get first and last changes for content
  local first_change = file_info.changes[1]
  local last_change = file_info.changes[#file_info.changes]

  -- Determine how to show the diff
  local net_operation = file_info.net_operation

  -- Parse old and new content based on net operation
  local old_lines = {}
  local new_lines = {}

  if net_operation == "created" then
    -- File was created in this session - show entire content as new
    old_lines = {}
    if last_change.new_content then
      new_lines = vim.split(last_change.new_content, "\n", { plain = true })
    else
      new_lines = { "(empty file)" }
    end
  elseif net_operation == "deleted" then
    -- File was deleted - show entire content as removed
    if first_change.old_content then
      old_lines = vim.split(first_change.old_content, "\n", { plain = true })
    else
      old_lines = { "(empty file)" }
    end
    new_lines = {}
  else
    -- File was modified - show diff from initial to final state
    if first_change.old_content then
      old_lines = vim.split(first_change.old_content, "\n", { plain = true })
    end
    if last_change.new_content then
      new_lines = vim.split(last_change.new_content, "\n", { plain = true })
    end
  end

  local hunks = diff_utils.calculate_hunks(old_lines, new_lines, 3)
  local ft = vim.filetype.match({ filename = filepath }) or ""

  set_option("modifiable", true, { buf = state.right_buf })
  api.nvim_buf_clear_namespace(state.right_buf, state.ns, 0, -1)
  render_diff(state.right_buf, state.ns, hunks, old_lines, new_lines)
  set_option("modifiable", false, { buf = state.right_buf })

  -- Set filetype for syntax highlighting AFTER making read-only
  -- This prevents ftplugin from interfering with buffer-local keymaps
  if ft and ft ~= "" then
    set_option("filetype", ft, { buf = state.right_buf })
    -- Reapply keymaps after setting filetype (ftplugin might override them)
    reapply_right_keymaps(state)
  end

  -- Update window title with operation indicator
  if api.nvim_win_is_valid(state.right_win) then
    local title_icon = " "
    if net_operation == "created" then
      title_icon = "󰙴 "
    elseif net_operation == "deleted" then
      title_icon = "󰧧 "
    end
    api.nvim_win_set_config(state.right_win, {
      title = string.format(" %s %s ", title_icon, vim.fn.fnamemodify(filepath, ":t")),
      title_pos = "center",
    })
  end
end

-- Navigate to next/previous file
---@param state table
---@param direction number
local function navigate_files(state, direction)
  if #state.summary.files == 0 then
    return
  end

  state.selected_file_idx = state.selected_file_idx or 1

  -- Move to next/previous file
  local new_file_idx = state.selected_file_idx + direction
  new_file_idx = math.max(1, math.min(new_file_idx, #state.summary.files))

  state.selected_file_idx = new_file_idx

  if api.nvim_win_is_valid(state.files_win) then
    pcall(api.nvim_win_set_cursor, state.files_win, { state.selected_file_idx, 0 })
  end

  update_preview(state, new_file_idx)

  render_file_list(state.files_buf, state.ns, state.summary.files, state.summary.by_file, state.selected_file_idx)
end

-- Filter changes up to selected checkpoint and regenerate view
---@param state table
---@param checkpoint_idx number
local function apply_checkpoint_filter(state, checkpoint_idx)
  if checkpoint_idx < 1 or checkpoint_idx > #state.checkpoints then
    return
  end

  local checkpoint = state.checkpoints[checkpoint_idx]
  state.selected_checkpoint_idx = checkpoint_idx

  -- Filter changes up to this checkpoint
  local filtered = {}
  for _, change in ipairs(state.all_changes) do
    if change.timestamp <= checkpoint.timestamp then
      table.insert(filtered, change)
    end
  end

  state.filtered_changes = filtered

  local summary = generate_summary(filtered)
  state.summary = summary

  -- Re-render file list with new summary
  state.selected_file_idx = 1
  render_file_list(state.files_buf, state.ns, summary.files, summary.by_file, state.selected_file_idx)
  render_checkpoints(state.checkpoints_buf, state.ns, state.checkpoints, state.all_changes, checkpoint_idx)

  -- Update preview with first file
  if #summary.files > 0 then
    pcall(api.nvim_win_set_cursor, state.files_win, { 1, 0 })
    update_preview(state, 1)
  else
    -- Clear preview if no files
    set_option("modifiable", true, { buf = state.right_buf })
    api.nvim_buf_set_lines(state.right_buf, 0, -1, false, { "", "No changes at this checkpoint", "" })
    set_option("modifiable", false, { buf = state.right_buf })
  end

  log:info("[FSDiff] Applied checkpoint filter: %d changes shown", #filtered)
end

-- Reset to show all changes
---@param state table
local function reset_checkpoint_filter(state)
  state.selected_checkpoint_idx = nil
  state.filtered_changes = state.all_changes

  -- Regenerate summary with all changes
  local summary = generate_summary(state.all_changes)
  state.summary = summary

  -- Re-render
  state.selected_file_idx = 1
  render_file_list(state.files_buf, state.ns, summary.files, summary.by_file, state.selected_file_idx)
  render_checkpoints(state.checkpoints_buf, state.ns, state.checkpoints, state.all_changes, nil)

  -- Update preview with first file
  if #summary.files > 0 then
    pcall(api.nvim_win_set_cursor, state.files_win, { 1, 0 })
    update_preview(state, 1)
  end

  log:info("[FSDiff] Reset to show all %d changes", #state.all_changes)
end

-- Close all windows
local function close_windows(state)
  if state.aug then
    pcall(api.nvim_del_augroup_by_id, state.aug)
    state.aug = nil
  end

  local windows = { state.files_win, state.checkpoints_win, state.right_win, state.help_win }
  for _, win in ipairs(windows) do
    if win and api.nvim_win_is_valid(win) then
      pcall(api.nvim_win_close, win, true)
    end
  end

  local buffers = { state.files_buf, state.checkpoints_buf, state.right_buf, state.help_buf }
  for _, buf in ipairs(buffers) do
    if buf and api.nvim_buf_is_valid(buf) then
      pcall(api.nvim_buf_delete, buf, { force = true })
    end
  end
end

-- Toggle help window
local function toggle_help(state)
  if state.help_win and api.nvim_win_is_valid(state.help_win) then
    pcall(api.nvim_win_close, state.help_win, true)
    if state.help_buf and api.nvim_buf_is_valid(state.help_buf) then
      pcall(api.nvim_buf_delete, state.help_buf, { force = true })
    end
    state.help_win = nil
    state.help_buf = nil
    return
  end

  local geom = calculate_geometry()
  local total_width = geom.left_w + geom.gap + geom.right_w
  local help_row = geom.row + geom.height + 1

  state.help_buf = api.nvim_create_buf(false, true)
  set_option("buftype", "nofile", { buf = state.help_buf })
  set_option("bufhidden", "wipe", { buf = state.help_buf })

  local help_text =
    " q/Esc: Close  |  ]f/[f: Next/Prev  |  Enter: Select checkpoint  |  r: Reset  |  Tab: Focus  |  ?: Toggle help "
  api.nvim_buf_set_lines(state.help_buf, 0, -1, false, { help_text })

  state.help_win = api.nvim_open_win(state.help_buf, false, {
    relative = "editor",
    row = help_row,
    col = geom.left_col,
    width = total_width,
    height = 1,
    style = "minimal",
    border = "rounded",
    zindex = 201,
  })

  vim.wo[state.help_win].wrap = false
end

-- Setup keymaps for all buffers
---@param state table
local function setup_keymaps(state)
  local keymaps = {
    -- stylua: ignore start
    { "n", "q", function() close_windows(state) end, "Close diff viewer", },
    { "n", "<Esc>", function() close_windows(state) end, "Close diff viewer", },
    { "n", "]f", function() navigate_files(state, 1) end, "Next file", },
    { "n", "[f", function() navigate_files(state, -1) end, "Previous file", },
    { "n", "j", function() navigate_files(state, 1) end, "Next file", },
    { "n", "k", function() navigate_files(state, -1) end, "Previous file", },
    { "n", "?", function() toggle_help(state) end, "Toggle help", },
    { "n", "<Tab>", function()
      local current = api.nvim_get_current_win()
      if current == state.files_win or current == state.checkpoints_win then
        api.nvim_set_current_win(state.right_win)
      else
        api.nvim_set_current_win(state.files_win)
      end
    end, "Toggle focus", },
    -- stylua: ignore end
  }

  -- Checkpoints buffer specific keymaps
  local checkpoint_keymaps = {
    -- stylua: ignore start
    { "n", "q", function() close_windows(state) end, "Close diff viewer", },
    { "n", "<Esc>", function() close_windows(state) end, "Close diff viewer", },
    { "n", "?", function() toggle_help(state) end, "Toggle help", },
    { "n", "<CR>", function()
      if #state.checkpoints == 0 then return end
      local cursor = api.nvim_win_get_cursor(state.checkpoints_win)
      local line = cursor[1]
      -- Subtract 2 for header lines
      local checkpoint_idx = line - 2
      if checkpoint_idx >= 1 and checkpoint_idx <= #state.checkpoints then
        apply_checkpoint_filter(state, checkpoint_idx)
      end
    end, "View checkpoint", },
    { "n", "r", function() reset_checkpoint_filter(state) end, "Reset to all changes", },
    { "n", "<Tab>", function()
      api.nvim_set_current_win(state.files_win)
    end, "Focus file list", },
    -- stylua: ignore end
  }

  -- Apply to files buffer
  for _, map in ipairs(keymaps) do
    local mode, lhs, rhs, desc = unpack(map)
    vim.keymap.set(mode, lhs, rhs, {
      buffer = state.files_buf,
      noremap = true,
      silent = true,
      nowait = true,
      desc = desc,
    })
  end

  -- Apply checkpoint-specific keymaps
  for _, map in ipairs(checkpoint_keymaps) do
    local mode, lhs, rhs, desc = unpack(map)
    vim.keymap.set(mode, lhs, rhs, {
      buffer = state.checkpoints_buf,
      noremap = true,
      silent = true,
      nowait = true,
      desc = desc,
    })
  end

  -- Right buffer gets limited keymaps
  -- Store keymaps in state so we can reapply them after filetype changes
  state.right_keymaps = {
    -- stylua: ignore start
    { "n", "q", function() close_windows(state) end, "Close diff viewer" },
    { "n", "<Esc>", function() close_windows(state) end, "Close diff viewer" },
    { "n", "?", function() toggle_help(state) end, "Toggle help" },
    { "n", "<Tab>", function() api.nvim_set_current_win(state.files_win) end, "Focus file list" },
    { "n", "]f", function() navigate_files(state, 1) end, "Next file", },
    { "n", "[f", function() navigate_files(state, -1) end, "Previous file", },
    -- stylua: ignore end
  }

  for _, map in ipairs(state.right_keymaps) do
    local mode, lhs, rhs, desc = unpack(map)
    vim.keymap.set(mode, lhs, rhs, {
      buffer = state.right_buf,
      noremap = true,
      silent = true,
      nowait = true,
      desc = desc,
    })
  end
end

-- Main entry point
---@param changes CodeCompanion.FSMonitor.Change[]
---@param checkpoints? CodeCompanion.FSMonitor.Checkpoint[]
function M.show(changes, checkpoints)
  if not changes or #changes == 0 then
    vim.notify("No file changes to display", vim.log.levels.INFO)
    return
  end

  checkpoints = checkpoints or {}

  setup_highlights()

  local geom = calculate_geometry()
  local summary = generate_summary(changes)

  local state = {
    files_buf = nil,
    checkpoints_buf = nil,
    right_buf = nil,
    files_win = nil,
    checkpoints_win = nil,
    right_win = nil,
    help_buf = nil,
    help_win = nil,
    ns = api.nvim_create_namespace("codecompanion_fs_diff"),
    aug = nil,
    summary = summary,
    checkpoints = checkpoints,
    all_changes = changes,
    filtered_changes = changes,
    selected_file_idx = 1,
    selected_checkpoint_idx = nil,
  }

  -- Create files buffer (top left)
  state.files_buf = api.nvim_create_buf(false, true)
  set_option("buftype", "nofile", { buf = state.files_buf })
  set_option("bufhidden", "wipe", { buf = state.files_buf })
  set_option("filetype", "codecompanion-fs-diff-files", { buf = state.files_buf })

  -- Create checkpoints buffer (bottom left)
  state.checkpoints_buf = api.nvim_create_buf(false, true)
  set_option("buftype", "nofile", { buf = state.checkpoints_buf })
  set_option("bufhidden", "wipe", { buf = state.checkpoints_buf })
  set_option("filetype", "codecompanion-fs-diff-checkpoints", { buf = state.checkpoints_buf })

  -- Create right buffer (diff preview)
  state.right_buf = api.nvim_create_buf(false, true)
  set_option("buftype", "nofile", { buf = state.right_buf })
  set_option("bufhidden", "wipe", { buf = state.right_buf })
  set_option("modifiable", false, { buf = state.right_buf })
  api.nvim_buf_set_name(state.right_buf, "codecompanion-fs-diff")

  -- Open files window (top left)
  state.files_win = api.nvim_open_win(state.files_buf, true, {
    relative = "editor",
    row = geom.row,
    col = geom.left_col,
    width = geom.left_w,
    height = geom.files_h,
    style = "minimal",
    border = "rounded",
    zindex = 200,
    title = "   Changed Files ",
    title_pos = "center",
  })

  -- Open checkpoints window (bottom left)
  state.checkpoints_win = api.nvim_open_win(state.checkpoints_buf, false, {
    relative = "editor",
    row = geom.checkpoints_row,
    col = geom.left_col,
    width = geom.left_w,
    height = geom.checkpoints_h,
    style = "minimal",
    border = "rounded",
    zindex = 200,
    title = "  Checkpoints ",
    title_pos = "center",
  })

  -- Open right window (diff preview)
  state.right_win = api.nvim_open_win(state.right_buf, false, {
    relative = "editor",
    row = geom.row,
    col = geom.right_col,
    width = geom.right_w,
    height = geom.height,
    style = "minimal",
    border = "rounded",
    zindex = 200,
    title = "  Diff Preview ",
    title_pos = "center",
  })

  -- Window options
  vim.wo[state.files_win].number = false
  vim.wo[state.files_win].relativenumber = false
  vim.wo[state.files_win].wrap = false
  vim.wo[state.files_win].cursorline = true

  vim.wo[state.checkpoints_win].number = false
  vim.wo[state.checkpoints_win].relativenumber = false
  vim.wo[state.checkpoints_win].wrap = false
  vim.wo[state.checkpoints_win].cursorline = true

  vim.wo[state.right_win].number = false
  vim.wo[state.right_win].relativenumber = false
  vim.wo[state.right_win].wrap = false
  vim.wo[state.right_win].cursorline = false
  vim.wo[state.right_win].scrollbind = false

  -- Render initial content
  render_file_list(state.files_buf, state.ns, summary.files, summary.by_file, state.selected_file_idx)
  render_checkpoints(state.checkpoints_buf, state.ns, checkpoints, changes, state.selected_checkpoint_idx)

  -- Setup keymaps
  setup_keymaps(state)

  -- Setup autocmds
  state.aug = api.nvim_create_augroup("CodeCompanionFSDiff", { clear = true })

  api.nvim_create_autocmd({ "CursorMoved" }, {
    group = state.aug,
    buffer = state.files_buf,
    callback = function()
      if not api.nvim_win_is_valid(state.files_win) then
        return
      end
      local cursor = api.nvim_win_get_cursor(state.files_win)
      local line = cursor[1]
      if line > 0 and line <= #summary.files then
        state.selected_file_idx = line
        update_preview(state, line)
        render_file_list(state.files_buf, state.ns, summary.files, summary.by_file, line)
      end
    end,
  })

  api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = state.aug,
    buffer = state.files_buf,
    callback = function()
      close_windows(state)
    end,
  })

  api.nvim_create_autocmd({ "WinClosed" }, {
    group = state.aug,
    callback = function()
      local all_valid = api.nvim_win_is_valid(state.files_win)
        and api.nvim_win_is_valid(state.checkpoints_win)
        and api.nvim_win_is_valid(state.right_win)
      if not all_valid then
        close_windows(state)
      end
    end,
  })

  api.nvim_create_autocmd({ "VimResized" }, {
    group = state.aug,
    callback = function()
      local g = calculate_geometry()
      if api.nvim_win_is_valid(state.files_win) then
        pcall(api.nvim_win_set_config, state.files_win, {
          relative = "editor",
          row = g.row,
          col = g.left_col,
          width = g.left_w,
          height = g.files_h,
        })
      end
      if api.nvim_win_is_valid(state.checkpoints_win) then
        pcall(api.nvim_win_set_config, state.checkpoints_win, {
          relative = "editor",
          row = g.checkpoints_row,
          col = g.left_col,
          width = g.left_w,
          height = g.checkpoints_h,
        })
      end
      if api.nvim_win_is_valid(state.right_win) then
        pcall(api.nvim_win_set_config, state.right_win, {
          relative = "editor",
          row = g.row,
          col = g.right_col,
          width = g.right_w,
          height = g.height,
        })
      end
    end,
  })

  -- Show initial preview (all changes by default)
  if #summary.files > 0 then
    pcall(api.nvim_win_set_cursor, state.files_win, { 1, 0 })
    update_preview(state, 1)
  end

  log:info(
    "[FSDiff] Opened with %d files, %d total changes, %d checkpoints",
    #summary.files,
    summary.total,
    #checkpoints
  )

  return state
end

return M
