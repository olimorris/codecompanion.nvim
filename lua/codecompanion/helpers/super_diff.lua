local Path = require("plenary.path")
local diff_utils = require("codecompanion.providers.diff.utils")
local edit_tracker = require("codecompanion.strategies.chat.edit_tracker")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local api = vim.api
local fmt = string.format
local ICONS = {
  accepted = " ",
  rejected = " ",
}

local COLORS = {
  accepted = "DiffAdded",
  rejected = "DiffDeleted",
}

local M = {}

---Get file extension for syntax highlighting
---@param filepath string
---@return string
local function get_file_extension(filepath)
  local ext = filepath:match("%.([^%.]+)$")
  if not ext then
    return "text"
  end
    -- Map common extensions to markdown language identifiers
    -- stylua: ignore start
    local ext_map = {
        js = "javascript", ts = "typescript", py = "python", rb = "ruby", rs = "rust", go = "go", java = "java",
        cpp = "cpp", c = "c", lua = "lua", vim = "vim", sh = "bash", zsh = "bash", fish = "fish", yml = "yaml",
        yaml = "yaml", json = "json", xml = "xml", html = "html", css = "css", scss = "scss", sass = "sass",
        md = "markdown", tex = "latex",
    }
  -- stylua: ignore end
  return ext_map[ext] or ext
end

---Format timestamp for display
---@param timestamp number
---@return string|osdate
local function format_timestamp(timestamp)
  local seconds = timestamp / 1000000000 -- Convert from nanoseconds to seconds
  return os.date("%H:%M:%S", seconds)
end

-- Helper function to debug log input from edit tracker
---@param tracked_files table
local function debug_log_input(tracked_files)
  for key, tracked_file in pairs(tracked_files) do
    log:debug("[SuperDiff] Input tracked file '%s' has %d operations", key, #tracked_file.edit_operations)
    for i, op in ipairs(tracked_file.edit_operations) do
      log:debug("[SuperDiff]   Operation %d: id=%s, tool=%s, status=%s", i, op.id, op.tool_name, op.status)
    end
  end
end

-- Helper function to group files by filepath and deduplicate operations
---@param tracked_files table
---@return table unique_files
local function group_and_deduplicate_files(tracked_files)
  debug_log_input(tracked_files)
  local unique_files = {}
  for key, tracked_file in pairs(tracked_files) do
    -- Create a normalized key based on file path
    local normalized_key
    if tracked_file.filepath then
      local p = Path:new(tracked_file.filepath)
      normalized_key = "file:" .. p:expand()
    else
      normalized_key = "buffer:" .. (tracked_file.bufnr or "unknown")
    end
    if not unique_files[normalized_key] then
      local display_name = tracked_file.filepath or ("Buffer " .. (tracked_file.bufnr or "unknown"))
      unique_files[normalized_key] = {
        tracked_file = tracked_file,
        operations = {},
        key = key,
        display_name = display_name,
      }
    end
    -- Add all operations to this file, avoiding duplicates by ID
    for _, op in ipairs(tracked_file.edit_operations) do
      local duplicate = false
      for _, existing_op in ipairs(unique_files[normalized_key].operations) do
        if existing_op.id == op.id then
          duplicate = true
          log:trace("[SuperDiff] Skipping duplicate operation: %s", op.id)
          break
        end
      end
      if not duplicate then
        table.insert(unique_files[normalized_key].operations, op)
        log:debug(
          "[SuperDiff] Added operation %s to file operations (total now: %d)",
          op.id,
          #unique_files[normalized_key].operations
        )
      else
        log:debug("[SuperDiff] Skipped duplicate operation %s", op.id)
      end
    end
  end
  return unique_files
end

-- Helper function to calculate file stats and display name
---@param file_data table
---@return table stats, string display_name, table tool_names
local function calculate_file_stats(file_data)
  local tracked_file = file_data.tracked_file
  local display_name = file_data.display_name
    or tracked_file.filepath
    or ("Buffer " .. (tracked_file.bufnr or "unknown"))
  if tracked_file.filepath then
    local p = Path:new(tracked_file.filepath)
    display_name = p:make_relative(vim.uv.cwd())
  end

  local stats = { accepted = 0, rejected = 0 }
  local tool_names = {}
  for _, op in ipairs(file_data.operations) do
    if op.status == "rejected" then
      stats.rejected = stats.rejected + 1
    else
      stats.accepted = stats.accepted + 1
    end
    if not vim.tbl_contains(tool_names, op.tool_name) then
      table.insert(tool_names, op.tool_name)
    end
  end

  return stats, display_name, tool_names
end

-- Helper function to process and sort operations
---@param file_data table
---@return table sorted_operations, table accepted_operations, table rejected_operations
local function process_operations(file_data)
  local sorted_operations = vim.deepcopy(file_data.operations)
  table.sort(sorted_operations, function(a, b)
    return a.timestamp < b.timestamp
  end)

  local accepted_operations = {}
  local rejected_operations = {}
  for _, op in ipairs(sorted_operations) do
    if op.status == "rejected" then
      table.insert(rejected_operations, op)
    else
      table.insert(accepted_operations, op)
    end
  end

  return sorted_operations, accepted_operations, rejected_operations
end

-- Helper function to get current content from buffer or file
---@param tracked_file table
---@return table|nil current_content
local function get_current_content(tracked_file)
  if tracked_file.type == "buffer" and tracked_file.bufnr and api.nvim_buf_is_valid(tracked_file.bufnr) then
    return api.nvim_buf_get_lines(tracked_file.bufnr, 0, -1, false)
  elseif tracked_file.filepath and vim.fn.filereadable(tracked_file.filepath) == 1 then
    return vim.fn.readfile(tracked_file.filepath)
  end
  return nil
end

-- Helper function to determine content for diff
---@param sorted_operations table
---@param accepted_operations table
---@param tracked_file table
---@return table|nil old_content, table|nil new_content
local function determine_diff_content(sorted_operations, accepted_operations, tracked_file)
  local earliest_original = nil
  local final_content = nil
  if #sorted_operations > 0 then
    earliest_original = sorted_operations[1].original_content
    -- For final content, use the last accepted operation's new_content if available
    if #accepted_operations > 0 then
      local last_accepted_op = accepted_operations[#accepted_operations]
      final_content = last_accepted_op.new_content
    else
      final_content = get_current_content(tracked_file) -- use it if no accepted operations
    end
  end
  local current_content = get_current_content(tracked_file) -- as fallback
  local old_content = earliest_original or current_content
  local new_content = final_content or current_content

  return old_content, new_content
end

-- Helper function to generate operations summary
---@param lines table
---@param file_data table
local function add_operations_summary(lines, file_data)
  table.insert(lines, "**Operations:**")
  for _, operation in ipairs(file_data.operations) do
    local status_icon = operation.status == "rejected" and ICONS.rejected or ICONS.accepted
    local timestamp_str = format_timestamp(operation.timestamp)
    local summary = fmt(
      "- %s %s by %s at %s",
      status_icon,
      operation.status == "rejected" and "REJECTED" or "ACCEPTED",
      operation.tool_name,
      timestamp_str
    )
    if operation.metadata and operation.metadata.explanation then
      summary = summary .. " - " .. operation.metadata.explanation
    end
    table.insert(lines, summary)
  end
  table.insert(lines, "")
end

-- Helper function to generate diff hunks display
---@param lines table
---@param diff_info table
---@param hunks table
---@param tracked_file table
---@param display_name string
---@return table line_mappings
local function add_diff_hunks(lines, diff_info, hunks, tracked_file, display_name)
  local lang = tracked_file.filepath and get_file_extension(tracked_file.filepath) or "text"
  table.insert(lines, "**Current State (Accepted Changes):**")
  table.insert(lines, "```" .. lang)
  local code_content_start = #lines
  local line_mappings = {}
  local buffer_line = code_content_start

  for hunk_idx, hunk in ipairs(hunks) do
    -- Add a line number indicator for context
    local line_indicator = fmt("@@ Line %d @@", hunk.old_start)
    table.insert(lines, line_indicator)
    buffer_line = buffer_line + 1

    -- Add removed lines
    for _, old_line in ipairs(hunk.old_lines) do
      table.insert(lines, old_line)
      buffer_line = buffer_line + 1
      table.insert(line_mappings, {
        buffer_line = buffer_line - 1,
        type = "removed",
        is_modification = #hunk.new_lines > 0,
      })
    end

    -- Add new lines
    for _, new_line in ipairs(hunk.new_lines) do
      table.insert(lines, new_line)
      buffer_line = buffer_line + 1
      table.insert(line_mappings, {
        buffer_line = buffer_line - 1,
        type = "added",
        is_modification = #hunk.old_lines > 0,
      })
    end

    -- Add spacing between hunks
    if hunk_idx < #hunks then
      table.insert(lines, "")
      buffer_line = buffer_line + 1
    end
  end

  table.insert(lines, "```")
  table.insert(lines, "")

  return line_mappings
end

-- Helper function to process accepted changes diff
---@param lines table
---@param diff_info table
---@param old_content table
---@param new_content table
---@param tracked_file table
---@param display_name string
---@param stats table
---@param file_data table
local function process_accepted_diff(
  lines,
  diff_info,
  old_content,
  new_content,
  tracked_file,
  display_name,
  stats,
  file_data
)
  if old_content and new_content and not diff_utils.contents_equal(old_content, new_content) then
    local hunks = diff_utils.calculate_hunks(old_content, new_content, 0)
    log:debug("[SuperDiff] File %s: calculated %d hunks for accepted changes", display_name, #hunks)
    if #hunks > 0 then
      local code_content_start = #lines + 1
      local line_mappings = add_diff_hunks(lines, diff_info, hunks, tracked_file, display_name)

      -- Store diff info for highlighting
      table.insert(diff_info, {
        start_line = code_content_start,
        end_line = #lines - 2,
        hunks = hunks,
        old_content = old_content,
        new_content = new_content,
        status = stats.rejected > 0 and "mixed" or "accepted",
        file_data = file_data,
        line_mappings = line_mappings,
      })
    else
      table.insert(lines, "*No content changes detected in accepted operations*")
      table.insert(lines, "")
    end
  else
    table.insert(lines, "*No differences found between original and current content*")
    table.insert(lines, "")
  end
end

-- Helper function to process rejected operations
---@param lines table
---@param diff_info table
---@param rejected_operations table
---@param tracked_file table
---@param file_data table
local function process_rejected_operations(lines, diff_info, rejected_operations, tracked_file, file_data)
  if #rejected_operations > 0 then
    table.insert(lines, "**Rejected Changes:**")
    for _, operation in ipairs(rejected_operations) do
      if operation.original_content and operation.new_content then
        local op_old_content = operation.original_content
        local op_new_content = operation.new_content

        if not diff_utils.contents_equal(op_old_content, op_new_content) then
          local op_hunks = diff_utils.calculate_hunks(op_old_content, op_new_content, 0)
          if #op_hunks > 0 then
            table.insert(lines, fmt("* REJECTED: %s*", operation.tool_name))
            if operation.metadata and operation.metadata.explanation then
              table.insert(lines, fmt("*%s*", operation.metadata.explanation))
            end

            local lang = tracked_file.filepath and get_file_extension(tracked_file.filepath) or "text"
            table.insert(lines, "```" .. lang)
            local code_content_start = #lines

            -- Create diff for this rejected operation
            local line_mappings = {}
            local buffer_line = code_content_start
            for hunk_idx, hunk in ipairs(op_hunks) do
              local line_indicator = fmt("@@ Line %d @@", hunk.old_start)
              table.insert(lines, line_indicator)
              buffer_line = buffer_line + 1

              -- Add removed lines
              for _, old_line in ipairs(hunk.old_lines) do
                table.insert(lines, old_line)
                buffer_line = buffer_line + 1
                table.insert(line_mappings, {
                  buffer_line = buffer_line - 1,
                  type = "removed",
                  is_modification = #hunk.new_lines > 0,
                })
              end

              -- Add new lines
              for _, new_line in ipairs(hunk.new_lines) do
                table.insert(lines, new_line)
                buffer_line = buffer_line + 1
                table.insert(line_mappings, {
                  buffer_line = buffer_line - 1,
                  type = "added",
                  is_modification = #hunk.old_lines > 0,
                })
              end

              if hunk_idx < #op_hunks then
                table.insert(lines, "")
                buffer_line = buffer_line + 1
              end
            end
            table.insert(lines, "```")
            table.insert(lines, "")

            -- Store diff info for highlighting rejected operations
            table.insert(diff_info, {
              start_line = code_content_start,
              end_line = #lines - 2,
              hunks = op_hunks,
              old_content = op_old_content,
              new_content = op_new_content,
              status = "rejected",
              file_data = file_data,
              line_mappings = line_mappings,
            })
          end
        end
      end
    end
  end
end

-- Helper function to process a single file's data
---@param file_data table
---@param lines table
---@param diff_info table
local function process_single_file(file_data, lines, diff_info)
  local section_start = #lines + 1
  local tracked_file = file_data.tracked_file

  local stats, display_name, tool_names = calculate_file_stats(file_data)

  local header = fmt("## %s", display_name)
  local accepted_icon = ICONS.accepted
  local rejected_icon = ICONS.rejected
  local stats_line = fmt(
    "*%d edits by %s: %d %s accepted, %d %s rejected*",
    #file_data.operations,
    table.concat(tool_names, ", "),
    stats.accepted,
    accepted_icon,
    stats.rejected,
    rejected_icon
  )
  table.insert(lines, header)
  table.insert(lines, stats_line)
  table.insert(lines, "")
  log:debug("[SuperDiff] Processing file %s with %d operations", display_name, #file_data.operations)

  -- Debug: Log the operations we're actually processing
  for i, op in ipairs(file_data.operations) do
    log:debug("[SuperDiff]   Processing operation %d: id=%s, tool=%s, status=%s", i, op.id, op.tool_name, op.status)
  end

  if #file_data.operations == 0 then
    table.insert(lines, "*No edit operations recorded*")
    table.insert(lines, "")
  else
    local sorted_operations, accepted_operations, rejected_operations = process_operations(file_data)
    local old_content, new_content = determine_diff_content(sorted_operations, accepted_operations, tracked_file)
    add_operations_summary(lines, file_data)
    process_accepted_diff(lines, diff_info, old_content, new_content, tracked_file, display_name, stats, file_data)
    process_rejected_operations(lines, diff_info, rejected_operations, tracked_file, file_data)
  end

  table.insert(lines, "---")
  table.insert(lines, "")

  return {
    start_line = section_start,
    end_line = #lines,
    display_name = display_name,
    file_data = file_data,
  }
end

---Generate unified markdown content showing consolidated file changes
---@param tracked_files table
---@return string[] lines, table[] file_sections, table[] diff_info
local function generate_markdown_super_diff(tracked_files)
  local lines = {}
  local file_sections = {}
  local diff_info = {}
  log:info("[SuperDiff] Generating unified markdown for %d tracked files", vim.tbl_count(tracked_files))
  local unique_files = group_and_deduplicate_files(tracked_files)
  for _, file_data in pairs(unique_files) do
    local file_section = process_single_file(file_data, lines, diff_info)
    table.insert(file_sections, file_section)
  end
  return lines, file_sections, diff_info
end

---Apply highlights to show edit operation status and changes
---@param bufnr integer
---@param diff_info table[]
---@param ns_id integer
local function apply_super_diff_highlights(bufnr, diff_info, ns_id)
  local all_extmark_ids = {}
  log:debug("[SuperDiff] Applying highlights for %d diff sections", #diff_info)
  for i, section in ipairs(diff_info) do
    if section.hunks and #section.hunks > 0 and section.line_mappings then
      -- Apply highlighting using stored line mappings from diff generation
      for _, mapping in ipairs(section.line_mappings) do
        local line_idx = mapping.buffer_line
        local change_type = mapping.type -- "added", "removed", "context"
        local is_modification = mapping.is_modification or false
        if line_idx >= 0 and line_idx < api.nvim_buf_line_count(bufnr) and change_type ~= "context" then
          local status = section.status == "mixed" and "pending" or section.status or "accepted"
          -- Get appropriate colors based on change type
          local line_hl, sign_text, sign_hl
          -- Get sign configuration from config (lazy load to avoid circular dependency)
          local config = require("codecompanion.config")
          local sign_config = config.display and config.display.diff and config.display.diff.signs or {}
          local highlight_groups = sign_config.highlight_groups
            or {
              addition = "DiagnosticOk",
              deletion = "DiagnosticError",
              modification = "DiagnosticWarn",
            }

          if change_type == "removed" then
            line_hl = "DiffDelete"
            sign_text = "▌"
            sign_hl = diff_utils.get_sign_highlight_for_change("removed", is_modification, highlight_groups)
          else -- added
            line_hl = status == "rejected" and "DiffDelete" or "DiffAdd"
            sign_text = status == "rejected" and "✗" or "▌"
            sign_hl = diff_utils.get_sign_highlight_for_change("added", is_modification, highlight_groups)
          end
          local extmark_id = api.nvim_buf_set_extmark(bufnr, ns_id, line_idx, 0, {
            line_hl_group = line_hl,
            priority = 100,
            sign_text = sign_text,
            sign_hl_group = sign_hl,
          })
          table.insert(all_extmark_ids, extmark_id)
        end
      end
    else
      log:debug("[SuperDiff] No hunks available for section %d", i)
    end
  end
  return all_extmark_ids
end

---Create and show the markdown super diff buffer
---@param chat CodeCompanion.Chat
---@param opts? table Optional window configuration overrides
function M.show_super_diff(chat, opts)
  opts = opts or {}
  local tracked_files = edit_tracker.get_tracked_edits(chat)
  if vim.tbl_isempty(tracked_files) then
    return utils.notify("No edits to show in this chat session")
  end

  -- Get super diff configuration with user overrides (lazy load to avoid circular dependency)
  local config = require("codecompanion.config")
  local super_diff_config = config.display and config.display.diff and config.display.diff.super_diff or {}
  local win_opts = vim.tbl_deep_extend("force", super_diff_config.win_opts or {}, opts or {})

  -- Set defaults for win_opts if not provided
  local default_win_opts = {
    relative = "editor",
    anchor = "NW",
    width = math.floor(vim.o.columns * 0.9),
    height = math.floor(vim.o.lines * 0.8),
    row = math.floor((vim.o.lines - math.floor(vim.o.lines * 0.8)) / 2),
    col = math.floor((vim.o.columns - math.floor(vim.o.columns * 0.9)) / 2),
    border = "rounded",
    title = " Super Diff ",
    title_pos = "center",
  }
  win_opts = vim.tbl_deep_extend("keep", win_opts, default_win_opts)

  -- Get comprehensive stats
  local stats = edit_tracker.get_edit_stats(chat)
  local lines, file_sections, diff_info = generate_markdown_super_diff(tracked_files)

  -- Create floating buffer with markdown filetype
  local ui = require("codecompanion.utils.ui")

  -- Update title with stats if not overridden
  if not opts or not opts.title then
    local simplified_accepted = stats.accepted_operations + stats.pending_operations
    win_opts.title = fmt(
      " Super Diff - Chat %d (%d files, %d operations: %d    %d  ) ",
      chat.id,
      stats.total_files,
      stats.total_operations,
      simplified_accepted,
      stats.rejected_operations
    )
  end

  -- Create window with configured options
  local bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false

  local winnr = api.nvim_open_win(bufnr, true, win_opts)
  vim.wo[winnr].number = true
  vim.wo[winnr].relativenumber = false

  local ns_id = api.nvim_create_namespace("codecompanion_super_diff")
  local _ = apply_super_diff_highlights(bufnr, diff_info, ns_id)
  M.setup_sticky_header(bufnr, winnr, lines)
  M.setup_keymaps(bufnr, chat, file_sections, ns_id)
  vim.api.nvim_win_call(winnr, function()
    vim.fn.matchadd(COLORS.accepted, vim.fn.escape(ICONS.accepted, "[]\\^$.*"), 100)
    vim.fn.matchadd(COLORS.rejected, vim.fn.escape(ICONS.rejected, "[]\\^$.*"), 100)
  end)
end

---Setup keymaps for the super diff buffer
---@param bufnr integer Buffer number for the super diff
---@param chat CodeCompanion.Chat Chat instance with tracked edits
---@param ns_id integer Namespace ID for highlights
function M.setup_keymaps(bufnr, chat, file_actions, ns_id)
  local function cleanup()
    if api.nvim_buf_is_valid(bufnr) then
      api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    end
    log:debug("[SuperDiff] Cleaned up highlights")
  end

  local function accept_all()
    local stats = edit_tracker.get_edit_stats(chat)
    local pending_count = stats.pending_operations
    local rejected_count = stats.rejected_operations
    local total_count = pending_count + rejected_count
    -- Accept all pending and rejected operations
    for _, tracked_file in pairs(edit_tracker.get_tracked_edits(chat)) do
      for _, operation in ipairs(tracked_file.edit_operations) do
        if operation.status == "pending" or operation.status == "rejected" then
          -- Apply the content to files/buffers
          if operation.new_content then
            if tracked_file.type == "buffer" and tracked_file.bufnr and api.nvim_buf_is_valid(tracked_file.bufnr) then
              api.nvim_buf_set_lines(tracked_file.bufnr, 0, -1, false, operation.new_content)
              log:debug("[SuperDiff] Applied content to buffer %d", tracked_file.bufnr)
            elseif tracked_file.filepath then
              vim.fn.writefile(operation.new_content, tracked_file.filepath)
              local file_bufnr = vim.fn.bufnr(tracked_file.filepath)
              if file_bufnr ~= -1 and api.nvim_buf_is_loaded(file_bufnr) then
                api.nvim_command("checktime " .. file_bufnr)
              end
              log:debug("[SuperDiff] Applied content to file %s", tracked_file.filepath)
            end
          end
          edit_tracker.update_edit_status(chat, operation.id, "accepted", operation.new_content)
          log:debug("[SuperDiff] Accepted operation %s", operation.id)
        end
      end
    end
    cleanup()
    if total_count > 0 then
      utils.notify(fmt(" Accepted all changes (%d operations)", total_count))
    else
      utils.notify("No changes to accept")
    end
    api.nvim_buf_delete(bufnr, { force = true })
  end

  local function reject_all()
    local stats = edit_tracker.get_edit_stats(chat)
    local pending_count = stats.pending_operations
    log:info("[SuperDiff] Rejecting all %d pending operations and reverting content", pending_count)
    for _, tracked_file in pairs(edit_tracker.get_tracked_edits(chat)) do
      -- Revert content to original state
      local original_content = nil
      if #tracked_file.edit_operations > 0 then
        original_content = tracked_file.edit_operations[1].original_content
      end
      if original_content then
        if tracked_file.type == "buffer" and tracked_file.bufnr and api.nvim_buf_is_valid(tracked_file.bufnr) then
          api.nvim_buf_set_lines(tracked_file.bufnr, 0, -1, false, original_content)
          log:debug("[SuperDiff] Reverted buffer %d to original content", tracked_file.bufnr)
        elseif tracked_file.filepath then
          vim.fn.writefile(original_content, tracked_file.filepath)
          local file_bufnr = vim.fn.bufnr(tracked_file.filepath)
          if file_bufnr ~= -1 and api.nvim_buf_is_loaded(file_bufnr) then
            api.nvim_command("checktime " .. file_bufnr)
          end
          log:debug("[SuperDiff] Reverted file %s to original content", tracked_file.filepath)
        end
      end
      -- Mark all operations as rejected
      for _, operation in ipairs(tracked_file.edit_operations) do
        if operation.status == "pending" then
          edit_tracker.update_edit_status(chat, operation.id, "rejected")
          log:debug("[SuperDiff] Rejected operation %s", operation.id)
        end
      end
    end
    cleanup()
    if pending_count > 0 then
      utils.notify(fmt(" Rejected all pending changes and reverted content (%d operations)", pending_count))
    else
      utils.notify("No pending changes to reject")
    end
    api.nvim_buf_delete(bufnr, { force = true })
  end
  vim.keymap.set("n", "ga", accept_all, { buffer = bufnr, desc = "Accept all pending changes", nowait = true })
  vim.keymap.set("n", "gr", reject_all, { buffer = bufnr, desc = "Reject all pending changes", nowait = true })
  vim.keymap.set("n", "gq", function()
    M.create_quickfix_list(chat)
  end, { buffer = bufnr, desc = "Add changes to quickfix list", nowait = true })
  vim.keymap.set("n", "q", function()
    cleanup()
    api.nvim_buf_delete(bufnr, { force = true })
  end, { buffer = bufnr, desc = "Close super diff" })
  log:debug("[SuperDiff] Keymaps configured: ga (accept all), gr (reject all), gq (quickfix), q (close)")
end

---Setup sticky header that follows cursor position and shows current file
---@param bufnr integer Buffer number for the super diff
---@param winnr integer Window number for the super diff
---@param lines string[] All lines in the buffer
function M.setup_sticky_header(bufnr, winnr, lines)
  local ns_id = api.nvim_create_namespace("codecompanion_super_diff_sticky")

  ---Find the current file header based on cursor position
  ---@param cursor_line integer 1-based cursor line number
  ---@return string|nil filename, string|nil relative_dir
  local function find_current_file_header(cursor_line)
    -- Look backwards from cursor to find the nearest ## header
    for i = cursor_line, 1, -1 do
      local line = lines[i]
      if line and line:match("^## ") then
        local full_path = line:match("^## (.+)")
        if full_path and full_path ~= "" then
          -- Handle buffer names (e.g., "Buffer 123")
          if full_path:match("^Buffer %d+") then
            return full_path, ""
          end
          local filename = vim.fs.basename(full_path)
          local dirname = vim.fs.dirname(full_path)
          local relative_dir = ""
          if dirname and dirname ~= "." and dirname ~= "" then
            relative_dir = dirname .. "/"
          end
          return filename, relative_dir
        end
      end
    end
    return nil, nil
  end

  ---Place or update the sticky header extmark
  ---@return nil
  local function update_sticky_header()
    if not api.nvim_win_is_valid(winnr) or not api.nvim_buf_is_valid(bufnr) then
      return
    end
    local ok, cursor_pos = pcall(api.nvim_win_get_cursor, winnr)
    if not ok or not cursor_pos then
      return
    end
    local cursor_line = cursor_pos[1] -- 1-based
    local top_line = vim.fn.line("w0", winnr) -- 1-based, first visible line
    local filename, relative_dir = find_current_file_header(cursor_line)
    pcall(api.nvim_buf_clear_namespace, bufnr, ns_id, 0, -1)
    if filename and filename ~= "" then
      local virt_text = {}
      table.insert(virt_text, { "[" .. filename .. "]", "CodeCompanionSuperDiffFilename" })
      if relative_dir and relative_dir ~= "" then
        table.insert(virt_text, { " : " .. relative_dir, "CodeCompanionSuperDiffDirectory" })
      end
      local used_width =
        vim.fn.strdisplaywidth("[" .. filename .. "]" .. (relative_dir ~= "" and " : " .. relative_dir or ""))
      local win_width = api.nvim_win_get_width(winnr)
      local padding_width = math.max(0, win_width - used_width)
      if padding_width > 0 then
        table.insert(virt_text, { string.rep(" ", padding_width), "CodeCompanionSuperDiffDirectory" })
      end
      pcall(api.nvim_buf_set_extmark, bufnr, ns_id, top_line - 1, 0, {
        virt_text = virt_text,
        virt_text_win_col = 0,
        line_hl_group = "Visual",
        priority = 1000,
      })
    end
  end

  local augroup = api.nvim_create_augroup("codecompanion_super_diff_sticky_" .. bufnr, { clear = true })
  -- Update on cursor movement and scrolling
  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "WinScrolled" }, {
    buffer = bufnr,
    group = augroup,
    callback = update_sticky_header,
  })
  api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    group = augroup,
    callback = function()
      api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    end,
  })
  update_sticky_header()

  log:debug("[SuperDiff] Sticky header setup complete for buffer %d", bufnr)
end

---Create quickfix list from accepted changes
---@param chat CodeCompanion.Chat
---@param opts? table Options: {include_rejected: boolean}
---@return number count Number of entries created
function M.create_quickfix_list(chat, opts)
  opts = opts or {}
  local tracked_files = edit_tracker.get_tracked_edits(chat)
  if vim.tbl_isempty(tracked_files) then
    utils.notify("No changes to add to quickfix list")
    return 0
  end
  local _, _, diff_info = generate_markdown_super_diff(tracked_files)
  local qf_items = {}
  for _, section in ipairs(diff_info) do
    if section.status == "rejected" and not opts.include_rejected then
      goto continue
    end
    local file_data = section.file_data
    local filename = file_data.tracked_file.filepath or ""
    if section.line_mappings then
      for _, mapping in ipairs(section.line_mappings) do
        if mapping.type ~= "context" then
          local icon = section.status == "rejected" and ICONS.rejected or ICONS.accepted
          local change = mapping.type == "added" and "Added" or "Deleted"

          table.insert(qf_items, {
            filename = filename,
            bufnr = file_data.tracked_file.bufnr,
            lnum = mapping.buffer_line + 1,
            col = 1,
            text = fmt("%s %s", icon, change),
            type = section.status == "rejected" and "E" or "I",
            valid = 1,
          })
        end
      end
    end

    ::continue::
  end

  if #qf_items > 0 then
    vim.fn.setqflist(qf_items, "r")
    vim.fn.setqflist({}, "a", { title = fmt("CodeCompanion Chat %d Changes", chat.id) })
    vim.cmd("copen")
    utils.notify(fmt("📝 Added %d changes to quickfix", #qf_items))
  end

  return #qf_items
end

return M
