local Path = require("plenary.path")
local config = require("codecompanion.config")
local diff_utils = require("codecompanion.providers.diff.utils")
local edit_tracker = require("codecompanion.strategies.chat.edit_tracker")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local api = vim.api
local fmt = string.format
local diff_signs_config = config.display.diff.diff_signs or {}

local ICONS = diff_signs_config.icons or {
  accepted = " ",
  rejected = " ",
}

local COLORS = diff_signs_config.colors or {
  accepted = "DiagnosticOk",
  rejected = "DiagnosticErro",
}

local SIGNS = diff_signs_config.signs
  or {
    text = "▌",
    reject = "✗",
    highlight_groups = {
      addition = "DiagnosticOk",
      deletion = "DiagnosticError",
      modification = "DiagnosticWarn",
    },
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

-- Helper function to group files by filepath and deduplicate operations
---@param tracked_files table
---@return table unique_files
local function group_and_deduplicate_files(tracked_files)
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
          log:trace("[helpers::super_diff::group_and_deduplicate_files] Skipping duplicate operation: %s", op.id)
          break
        end
      end
      if not duplicate then
        table.insert(unique_files[normalized_key].operations, op)
      else
        log:debug("[helpers::super_diff::group_and_deduplicate_files] Skipped duplicate operation %s", op.id)
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
    -- For final content, use the last accepted operation's new_content
    if #accepted_operations > 0 then
      local last_accepted_op = accepted_operations[#accepted_operations]
      final_content = last_accepted_op.new_content
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

-- Helper function to calculate accepted hunks for a file
---@param file_data table
---@return string[]|nil old_content, string[]|nil new_content, table hunks
local function calculate_file_accepted_hunks(file_data)
  local tracked_file = file_data.tracked_file
  local display_name = file_data.display_name
  local sorted_operations, accepted_operations, _ = process_operations(file_data)
  if #accepted_operations == 0 then
    return nil, nil, {}
  end
  local old_content, new_content = determine_diff_content(sorted_operations, accepted_operations, tracked_file)
  if old_content and new_content and not diff_utils.contents_equal(old_content, new_content) then
    local hunks = diff_utils.calculate_hunks(old_content, new_content, 0)
    return old_content, new_content, hunks
  end

  return old_content, new_content, {}
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
  local calc_old_content, calc_new_content, hunks = calculate_file_accepted_hunks({
    tracked_file = tracked_file,
    display_name = display_name,
    operations = file_data.operations,
  })
  if #hunks > 0 then
    local code_content_start = #lines + 1
    local line_mappings = add_diff_hunks(lines, diff_info, hunks, tracked_file, display_name)
    -- Store diff info for highlighting
    table.insert(diff_info, {
      start_line = code_content_start,
      end_line = #lines - 2,
      hunks = hunks,
      old_content = calc_old_content,
      new_content = calc_new_content,
      status = stats.rejected > 0 and "mixed" or "accepted",
      file_data = file_data,
      line_mappings = line_mappings,
    })
  else
    table.insert(lines, "*No content changes detected in accepted operations*")
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
  log:debug(
    "[helpers::super_diff::process_single_file] Processing file %s with %d operations",
    display_name,
    #file_data.operations
  )
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
  log:info(
    "[helpers::super_diff::generate_markdown_super_diff] Generating super_diff for %d tracked files",
    vim.tbl_count(tracked_files)
  )
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

          if change_type == "removed" then
            line_hl = "DiffDelete"
            sign_text = status == "rejected" and SIGNS.reject or SIGNS.text
            sign_hl = diff_utils.get_sign_highlight_for_change("removed", is_modification, SIGNS.highlight_groups)
          else -- added
            line_hl = "DiffAdd"
            sign_text = status == "rejected" and SIGNS.reject or SIGNS.text
            sign_hl = diff_utils.get_sign_highlight_for_change("added", is_modification, SIGNS.highlight_groups)
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
      log:debug("[helpers::super_diff::apply_super_diff_highlights] No hunks available for section %d", i)
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

  local stats = edit_tracker.get_edit_stats(chat)
  local lines, file_sections, diff_info = generate_markdown_super_diff(tracked_files)

  local ui = require("codecompanion.utils.ui")
  local window_config = config.display.chat.debug_and_super_diff_window
  local title = opts.title
  if not title then
    local simplified_accepted = stats.accepted_operations + stats.pending_operations
    title = fmt(
      " Super Diff - Chat %d (%d files, %d operations: %d %s %d %s) ",
      chat.id,
      stats.total_files,
      stats.total_operations,
      simplified_accepted,
      ICONS.accepted,
      stats.rejected_operations,
      ICONS.rejected
    )
  end

  local bufnr, winnr = ui.create_float(lines, {
    filetype = "markdown",
    title = title,
    window = window_config,
    ignore_keymaps = true,
  })

  api.nvim_buf_set_name(bufnr, "CodeCompanion_super_diff")
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].modifiable = true
  if window_config.opts then
    ui.set_win_options(winnr, window_config.opts)
  else
    vim.wo[winnr].number = true
    vim.wo[winnr].relativenumber = false
  end
  pcall(api.nvim_win_set_cursor, winnr, { 2, 0 })
  local ns_id = api.nvim_create_namespace("codecompanion_super_diff")
  local _ = apply_super_diff_highlights(bufnr, diff_info, ns_id)
  M.setup_sticky_header(bufnr, winnr, lines)
  M.setup_keymaps(bufnr, chat, file_sections, ns_id)
  vim.api.nvim_win_call(winnr, function()
    vim.fn.matchadd(COLORS.accepted, ICONS.accepted, 100)
    vim.fn.matchadd(COLORS.rejected, ICONS.rejected, 100)
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
            elseif tracked_file.filepath then
              vim.fn.writefile(operation.new_content, tracked_file.filepath)
              local file_bufnr = vim.fn.bufnr(tracked_file.filepath)
              if file_bufnr ~= -1 and api.nvim_buf_is_loaded(file_bufnr) then
                api.nvim_command("checktime " .. file_bufnr)
              end
            end
          end
          edit_tracker.update_edit_status(chat, operation.id, "accepted", operation.new_content)
          log:debug("[helpers::super_diff::setup_keymaps] Accepted operation %s", operation.id)
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
    for _, tracked_file in pairs(edit_tracker.get_tracked_edits(chat)) do
      -- Revert content to original state
      local original_content = nil
      if #tracked_file.edit_operations > 0 then
        original_content = tracked_file.edit_operations[1].original_content
      end
      if original_content then
        if tracked_file.type == "buffer" and tracked_file.bufnr and api.nvim_buf_is_valid(tracked_file.bufnr) then
          api.nvim_buf_set_lines(tracked_file.bufnr, 0, -1, false, original_content)
          log:debug("[helpers::super_diff::setup_keymaps] Reverted buffer %d to original content", tracked_file.bufnr)
        elseif tracked_file.filepath then
          vim.fn.writefile(original_content, tracked_file.filepath)
          local file_bufnr = vim.fn.bufnr(tracked_file.filepath)
          if file_bufnr ~= -1 and api.nvim_buf_is_loaded(file_bufnr) then
            api.nvim_command("checktime " .. file_bufnr)
          end
          log:debug("[helpers::super_diff::setup_keymaps] Reverted file %s to original content", tracked_file.filepath)
        end
      end
      -- Mark all operations as rejected
      for _, operation in ipairs(tracked_file.edit_operations) do
        if operation.status == "pending" then
          edit_tracker.update_edit_status(chat, operation.id, "rejected")
          log:debug("[helpers::super_diff::setup_keymaps] Rejected operation %s", operation.id)
        end
      end
    end
    cleanup()
    if pending_count > 0 then
      utils.notify(fmt(" Rejected all changes and reverted content (%d operations)", pending_count))
    else
      utils.notify("No pending changes to reject")
    end
    api.nvim_buf_delete(bufnr, { force = true })
  end
  vim.keymap.set("n", "ga", accept_all, { buffer = bufnr, desc = "Accept all changes", nowait = true })
  vim.keymap.set("n", "gr", reject_all, { buffer = bufnr, desc = "Reject all changes", nowait = true })
  vim.keymap.set("n", "gq", function()
    local count = M.create_quickfix_list(chat)
    if count > 0 then
      cleanup()
      api.nvim_buf_delete(bufnr, { force = true })
    end
  end, { buffer = bufnr, desc = "Add changes to quickfix list", nowait = true })
  vim.keymap.set("n", "q", function()
    cleanup()
    api.nvim_buf_delete(bufnr, { force = true })
  end, { buffer = bufnr, desc = "Close super diff" })
end

---Setup sticky header that follows cursor position and shows current file
---@param bufnr integer Buffer number for the super diff
---@param winnr integer Window number for the super diff
---@param lines string[] All lines in the buffer
function M.setup_sticky_header(bufnr, winnr, lines)
  local sticky_win = nil
  local sticky_buf = nil
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

  ---Apply colored highlights to sticky header buffer
  ---@param buffer number Buffer to apply highlights to
  ---@param filename_part string The [filename] part
  ---@param dir_part string The : dir/ part
  ---@param keymap_part string The | keymaps part
  ---@param padding_left number Left padding amount
  ---@return nil
  local function apply_sticky_header_colors(buffer, filename_part, dir_part, keymap_part, padding_left)
    local ns_id = api.nvim_create_namespace("sticky_header_highlights")
    api.nvim_buf_clear_namespace(buffer, ns_id, 0, -1)
    -- Color the filename part [filename]
    local filename_start = padding_left
    local filename_end = filename_start + vim.fn.strdisplaywidth(filename_part)
    api.nvim_buf_set_extmark(buffer, ns_id, 0, filename_start, {
      end_col = filename_end,
      hl_group = "CodeCompanionChatError",
    })
    -- Color the relative path part
    if dir_part ~= "" then
      local dir_start = filename_end
      local dir_end = dir_start + vim.fn.strdisplaywidth(dir_part)
      api.nvim_buf_set_extmark(buffer, ns_id, 0, dir_start, {
        end_col = dir_end,
        hl_group = "CodeCompanionChatInfo",
      })
    end
    -- Color the keymap part
    local keymap_start = filename_end + vim.fn.strdisplaywidth(dir_part)
    local keymap_end = keymap_start + vim.fn.strdisplaywidth(keymap_part)
    api.nvim_buf_set_extmark(buffer, ns_id, 0, keymap_start, {
      end_col = keymap_end,
      hl_group = "CodeCompanionChatTokens",
    })
  end

  ---Create or update sticky header window with colored text
  ---@param filename string Filename to display
  ---@param relative_dir string Relative directory path
  ---@return nil
  local function create_or_update_sticky_window(filename, relative_dir)
    if not api.nvim_win_is_valid(winnr) then
      return
    end
    local win_width = api.nvim_win_get_width(winnr)
    -- Build header text components
    local filename_part = "[" .. filename .. "]"
    local dir_part = relative_dir and relative_dir ~= "" and (" : " .. relative_dir) or ""
    local keymap_part = " | ga: accept all | gr: reject all | gq: quickfix"
    local full_text = filename_part .. dir_part .. keymap_part
    local auto_mode = vim.g.codecompanion_auto_tool_mode
    local auto_status = auto_mode and " [AUTO: ON]" or " [AUTO: OFF]"
    local text_width = vim.fn.strdisplaywidth(full_text)
    local padding_left = math.max(0, math.floor((win_width - text_width) / 2))
    local padding_right = math.max(0, win_width - text_width - padding_left)
    local padded_text = string.rep(" ", padding_left)
      .. full_text
      .. string.rep(" ", padding_right - vim.fn.strdisplaywidth(auto_status))
      .. auto_status
    if sticky_win and api.nvim_win_is_valid(sticky_win) and sticky_buf and api.nvim_buf_is_valid(sticky_buf) then
      vim.bo[sticky_buf].modifiable = true
      api.nvim_buf_set_lines(sticky_buf, 0, -1, false, { padded_text })
      vim.bo[sticky_buf].modifiable = false
      api.nvim_win_set_config(sticky_win, { width = win_width })
      apply_sticky_header_colors(sticky_buf, filename_part, dir_part, keymap_part, padding_left)
      return
    end
    -- Create new header sticky buf/window [because of render-markdown plugin :( ]
    sticky_buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(sticky_buf, 0, -1, false, { padded_text })
    vim.bo[sticky_buf].buftype = "nofile"
    vim.bo[sticky_buf].bufhidden = "wipe"
    sticky_win = api.nvim_open_win(sticky_buf, false, {
      relative = "win",
      focusable = false,
      win = winnr,
      anchor = "NW",
      row = 0,
      col = 0,
      width = win_width,
      height = 1,
      style = "minimal",
      border = "none",
      zindex = 1000,
    })
    vim.wo[sticky_win].winhighlight = "Normal:Visual"
    apply_sticky_header_colors(sticky_buf, filename_part, dir_part, keymap_part, padding_left)
  end

  ---Clean up sticky window
  ---@return nil
  local function cleanup_sticky_window()
    if sticky_win and api.nvim_win_is_valid(sticky_win) then
      api.nvim_win_close(sticky_win, true)
    end
    sticky_win = nil
    sticky_buf = nil
  end

  ---Update sticky header content
  ---@return nil
  local function update_sticky_header()
    if not api.nvim_win_is_valid(winnr) or not api.nvim_buf_is_valid(bufnr) then
      cleanup_sticky_window()
      return
    end
    local ok, cursor_pos = pcall(api.nvim_win_get_cursor, winnr)
    if not ok or not cursor_pos then
      return
    end
    local cursor_line = cursor_pos[1] -- 1-based
    local filename, relative_dir = find_current_file_header(cursor_line)

    if filename and filename ~= "" then
      create_or_update_sticky_window(filename, relative_dir or "")
    else
      cleanup_sticky_window()
    end
  end

  local augroup = api.nvim_create_augroup("codecompanion_super_diff_sticky_" .. bufnr, { clear = true })
  api.nvim_create_autocmd({ "CursorMoved", "WinScrolled" }, {
    buffer = bufnr,
    group = augroup,
    callback = update_sticky_header,
  })
  api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = augroup,
    desc = "Update sticky header on window/vim resize",
    callback = function()
      update_sticky_header()
    end,
  })
  api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    group = augroup,
    callback = function()
      cleanup_sticky_window()
    end,
  })
  update_sticky_header()

  log:debug("[helpers::super_diff::setup_sticky_header] Sticky header setup complete for buffer %d", bufnr)
end

---Create quickfix list from accepted changes only, grouped by hunks
---@param chat CodeCompanion.Chat
---@return number count Number of entries created
function M.create_quickfix_list(chat)
  local tracked_files = edit_tracker.get_tracked_edits(chat)
  if vim.tbl_isempty(tracked_files) then
    log:debug("[helpers::super_diff::create_quickfix_list] No tracked files found")
    utils.notify("No changes to add to quickfix list")
    return 0
  end
  local unique_files = group_and_deduplicate_files(tracked_files)
  local qf_items = {}
  local accepted_operations_count = 0

  for _, file_data in pairs(unique_files) do
    local tracked_file = file_data.tracked_file
    local display_name = file_data.display_name
    local _, _, hunks = calculate_file_accepted_hunks(file_data)
    if #hunks > 0 then
      accepted_operations_count = accepted_operations_count + 1
      for _, hunk in ipairs(hunks) do
        local filename = tracked_file.filepath or ""
        local line_num = hunk.old_start - 1 -- 0-based indexing
        local added_count = #hunk.new_lines
        local deleted_count = #hunk.old_lines
        -- Get sample line content to show what was changed
        local line_content = ""
        if added_count > 0 and #hunk.new_lines > 0 then
          line_content = hunk.new_lines[1]:gsub("^%s*", ""):gsub("%s*$", "") -- trim whitespace
        elseif deleted_count > 0 and #hunk.old_lines > 0 then
          line_content = hunk.old_lines[1]:gsub("^%s*", ""):gsub("%s*$", "") -- trim whitespace
        end
        local change_type = ""
        if added_count > 0 and deleted_count > 0 then
          change_type = fmt("Modified (+%d -%d): %s", added_count, deleted_count, line_content)
        elseif added_count > 0 then
          change_type = fmt("Added (+%d): %s", added_count, line_content)
        else
          change_type = fmt("Deleted (-%d): %s", deleted_count, line_content)
        end

        table.insert(qf_items, {
          filename = filename,
          bufnr = tracked_file.bufnr,
          lnum = line_num,
          col = 1,
          text = fmt("%s %s", ICONS.accepted, change_type),
          type = "I",
          valid = 1,
        })
      end
    else
      log:debug(
        "[helpers::super_diff::create_quickfix_list] No accepted changes or content differences for file %s",
        display_name
      )
    end
  end

  if #qf_items > 0 then
    vim.fn.setqflist(qf_items, "r")
    vim.fn.setqflist({}, "a", { title = fmt("CodeCompanion Chat %d Accepted Changes", chat.id) })
    vim.cmd("copen")
    utils.notify(fmt("Added %d changes to quickfix", #qf_items))
  else
    utils.notify("No accepted changes to add to quickfix list")
  end

  return #qf_items
end

return M
