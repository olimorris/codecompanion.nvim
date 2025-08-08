local api = vim.api
local Path = require("plenary.path")
local diff_utils = require("codecompanion.providers.diff.utils")
local edit_tracker = require("codecompanion.strategies.chat.edit_tracker")
local log = require("codecompanion.utils.log")

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

---Get status indicator for edit operation
---@param status string
---@return string, string # Icon and color
local function get_status_indicator(status)
  if status == "accepted" then
    return "✔️", "DiffAdd"
  elseif status == "rejected" then
    return " ", "DiffDelete"
  else
    -- Convert pending to accepted for simplicity
    return "✔️", "DiffAdd"
  end
end

---Format timestamp for display
---@param timestamp number
---@return string|osdate
local function format_timestamp(timestamp)
  local seconds = timestamp / 1000000000 -- Convert from nanoseconds to seconds
  return os.date("%H:%M:%S", seconds)
end

---Generate unified markdown content showing consolidated file changes
---@param tracked_files table
---@return string[] lines, table[] file_sections, table[] diff_info
local function generate_markdown_super_diff(tracked_files)
  local lines = {}
  local file_sections = {}
  local diff_info = {}
  log:info("[SuperDiff] Generating unified markdown for %d tracked files", vim.tbl_count(tracked_files))
  -- Group files by actual filepath to avoid duplicates
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
    -- Add all operations to this file, avoiding duplicates by ID and timestamp
    for _, op in ipairs(tracked_file.edit_operations) do
      local duplicate = false
      for _, existing_op in ipairs(unique_files[normalized_key].operations) do
        if
          existing_op.id == op.id
          or (existing_op.tool_name == op.tool_name and math.abs(existing_op.timestamp - op.timestamp) < 1000000000)
        then -- 1 second window
          duplicate = true
          log:trace("[SuperDiff] Skipping duplicate operation: %s", op.id)
          break
        end
      end
      if not duplicate then
        table.insert(unique_files[normalized_key].operations, op)
      end
    end
  end
  for _, file_data in pairs(unique_files) do
    local section_start = #lines + 1
    local tracked_file = file_data.tracked_file
    -- File header in markdown
    local display_name = file_data.display_name
      or tracked_file.filepath
      or ("Buffer " .. (tracked_file.bufnr or "unknown"))
    if tracked_file.filepath then
      local p = Path:new(tracked_file.filepath)
      display_name = p:make_relative(vim.fn.getcwd())
    end
    -- Count operations by status (treat pending as accepted)
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
    local header = string.format("## %s", display_name)
    local stats_line = string.format(
      "*%d edits by %s: %d ✔️accepted, %d ❌ rejected*",
      #file_data.operations,
      table.concat(tool_names, ", "),
      stats.accepted,
      stats.rejected
    )
    table.insert(lines, header)
    table.insert(lines, stats_line)
    table.insert(lines, "")
    log:debug("[SuperDiff] Processing file %s with %d operations", display_name, #file_data.operations)
    if #file_data.operations == 0 then
      table.insert(lines, "*No edit operations recorded*")
      table.insert(lines, "")
    else
      -- Get the earliest original content and determine final content
      local earliest_original = nil
      local final_content = nil
      local earliest_time = math.huge
      -- Sort operations by timestamp to get correct sequence
      local sorted_operations = vim.deepcopy(file_data.operations)
      table.sort(sorted_operations, function(a, b)
        return a.timestamp < b.timestamp
      end)
      if #sorted_operations > 0 then
        earliest_original = sorted_operations[1].original_content
        -- For final content, use the last operation's new_content if available
        local last_op = sorted_operations[#sorted_operations]
        final_content = last_op.new_content
      end
      -- Get current content as fallback
      local current_content
      if tracked_file.type == "buffer" and tracked_file.bufnr and api.nvim_buf_is_valid(tracked_file.bufnr) then
        current_content = api.nvim_buf_get_lines(tracked_file.bufnr, 0, -1, false)
      elseif tracked_file.filepath and vim.fn.filereadable(tracked_file.filepath) == 1 then
        current_content = vim.fn.readfile(tracked_file.filepath)
      end
      -- Use best available content
      local old_content = earliest_original or current_content
      local new_content = final_content or current_content
      if old_content and new_content and not diff_utils.contents_equal(old_content, new_content) then
        -- Calculate hunks with minimal context (0 lines) to show only changes
        local hunks = diff_utils.calculate_hunks(old_content, new_content, 0)
        log:debug("[SuperDiff] File %s: calculated %d hunks", display_name, #hunks)
        if #hunks > 0 then
          local lang = tracked_file.filepath and get_file_extension(tracked_file.filepath) or "text"
          -- Show tool operations summary
          table.insert(lines, "**Operations:**")
          for i, operation in ipairs(file_data.operations) do
            local status_icon, _ = get_status_indicator(operation.status)
            local timestamp_str = format_timestamp(operation.timestamp)
            local summary = string.format(
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
          -- Single unified code block showing only actual changes
          table.insert(lines, "```" .. lang)
          local code_content_start = #lines
          -- Create simplified diff showing only changed lines with minimal context
          local line_mappings = {}
          local buffer_line = code_content_start
          for hunk_idx, hunk in ipairs(hunks) do
            -- Add a line number indicator for context
            local line_indicator = string.format("@@ Line %d @@", hunk.old_start)
            table.insert(lines, line_indicator)
            buffer_line = buffer_line + 1
            -- Add removed lines with - prefix
            for _, old_line in ipairs(hunk.old_lines) do
              local display_line = old_line
              table.insert(lines, display_line)
              buffer_line = buffer_line + 1
              table.insert(line_mappings, {
                buffer_line = buffer_line - 1,
                type = "removed",
                is_modification = #hunk.new_lines > 0,
              })
            end

            -- Add new lines with + prefix
            for _, new_line in ipairs(hunk.new_lines) do
              local display_line = new_line
              table.insert(lines, display_line)
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
          table.insert(lines, "*No content changes detected*")
          table.insert(lines, "")
        end
      else
        table.insert(lines, "*No differences found between original and current content*")
        table.insert(lines, "")
      end
    end
    table.insert(lines, "---")
    table.insert(lines, "")
    table.insert(file_sections, {
      key = file_data.key,
      tracked_file = tracked_file,
      start_line = section_start,
      end_line = #lines,
      operations = file_data.operations,
    })
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
          if change_type == "removed" then
            line_hl = "DiffDelete"
            sign_text = "▌"
            sign_hl = diff_utils.get_sign_highlight_for_change("removed", is_modification, status)
          else -- added
            line_hl = status == "rejected" and "DiffDelete" or "DiffAdd"
            sign_text = status == "rejected" and "✗" or "▌"
            sign_hl = diff_utils.get_sign_highlight_for_change("added", is_modification, status)
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
function M.show_super_diff(chat)
  local tracked_files = edit_tracker.get_tracked_edits(chat)
  if vim.tbl_isempty(tracked_files) then
    vim.notify("No edits to show in this chat session", vim.log.levels.INFO, { title = "CodeCompanion" })
    return
  end
  -- Get comprehensive stats
  local stats = edit_tracker.get_edit_stats(chat)
  local lines, file_sections, diff_info = generate_markdown_super_diff(tracked_files)
  -- Create floating buffer with markdown filetype
  local ui = require("codecompanion.utils.ui")
  -- Simplify stats - treat pending as accepted
  local simplified_accepted = stats.accepted_operations + stats.pending_operations
  local title = string.format(
    "Super Diff - Chat %d (%d files, %d operations: %d ✔️ %d  )",
    chat.id,
    stats.total_files,
    stats.total_operations,
    simplified_accepted,
    stats.rejected_operations
  )
  local bufnr, winnr = ui.create_float(lines, {
    filetype = "markdown",
    title = title,
    window = {
      width = math.min(160, vim.o.columns - 20),
      height = math.min(60, vim.o.lines - 10),
      row = "center",
      col = "center",
    },
    relative = "editor",
    lock = true,
    ignore_keymaps = true,
  })
  vim.wo[winnr].number = true
  vim.wo[winnr].relativenumber = false
  local ns_id = api.nvim_create_namespace("codecompanion_super_diff")
  local _ = apply_super_diff_highlights(bufnr, diff_info, ns_id)
  M.setup_sticky_header(bufnr, winnr, lines)
  M.setup_keymaps(bufnr, chat, file_sections, ns_id)
end

---Setup keymaps for the super diff buffer
---@param bufnr integer Buffer number for the super diff
---@param chat CodeCompanion.Chat
---@param file_sections table[] File sections with edit operations
---@param ns_id integer Namespace ID for highlights
function M.setup_keymaps(bufnr, chat, file_sections, ns_id)
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
      vim.notify(string.format("✔️Accepted all changes (%d operations)", total_count, { title = "CodeCompanion" }))
    else
      vim.notify("No changes to accept", vim.log.levels.INFO, { title = "CodeCompanion" })
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
      vim.notify(
        string.format(" Rejected all pending changes and reverted content (%d operations)", pending_count),
        { title = "CodeCompanion" }
      )
    else
      vim.notify("No pending changes to reject", vim.log.levels.INFO, { title = "CodeCompanion" })
    end
    api.nvim_buf_delete(bufnr, { force = true })
  end
  vim.keymap.set("n", "ga", accept_all, { buffer = bufnr, desc = "Accept all pending changes", nowait = true })
  vim.keymap.set("n", "gr", reject_all, { buffer = bufnr, desc = "Reject all pending changes", nowait = true })
  vim.keymap.set("n", "q", function()
    cleanup()
    api.nvim_buf_delete(bufnr, { force = true })
  end, { buffer = bufnr, desc = "Close super diff" })
  log:debug("[SuperDiff] Keymaps configured: ga (accept all), gr (reject all), q (close)")
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

return M
