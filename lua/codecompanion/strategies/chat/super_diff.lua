local api = vim.api
local InlineDiff = require("codecompanion.providers.diff.inline")
local Path = require("plenary.path")
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

---Calculate line ranges for hunks in original file
---@param hunks table[]
---@return table[] ranges
local function calculate_line_ranges(hunks)
  local ranges = {}
  for _, hunk in ipairs(hunks) do
    local start_line, end_line
    if hunk.old_count == 0 then
      -- Pure addition - show where it was inserted
      start_line = hunk.new_start
      end_line = hunk.new_start + hunk.new_count - 1
    elseif hunk.new_count == 0 then
      -- Pure deletion - show where it was deleted from
      start_line = hunk.old_start
      end_line = hunk.old_start + hunk.old_count - 1
    else
      -- Modification - show the affected range
      start_line = math.min(hunk.old_start, hunk.new_start)
      end_line = math.max(hunk.old_start + hunk.old_count - 1, hunk.new_start + hunk.new_count - 1)
    end

    table.insert(ranges, {
      start_line = start_line,
      end_line = end_line,
    })
  end

  return ranges
end

---Generate markdown content with fenced code blocks and line numbers
---@param tracked_edits table
---@return string[] lines, table[] file_sections, table[] diff_info
local function generate_markdown_super_diff(tracked_edits)
  local lines = {}
  local file_sections = {}
  local diff_info = {}

  for key, edit_info in pairs(tracked_edits) do
    local section_start = #lines + 1
    -- File header in markdown
    local display_name = edit_info.filepath or ("Buffer " .. edit_info.bufnr)
    if edit_info.filepath then
      local p = Path:new(edit_info.filepath)
      display_name = p:make_relative(vim.fn.getcwd())
    end
    local header = string.format("## %s", display_name)
    if #edit_info.tool_names > 0 then
      header = header .. " *(edited by: " .. table.concat(edit_info.tool_names, ", ") .. ")*"
    end
    table.insert(lines, header)
    table.insert(lines, "")

    local current_content
    if edit_info.type == "buffer" and edit_info.bufnr and api.nvim_buf_is_valid(edit_info.bufnr) then
      current_content = api.nvim_buf_get_lines(edit_info.bufnr, 0, -1, false)
    elseif edit_info.filepath and vim.fn.filereadable(edit_info.filepath) == 1 then
      current_content = vim.fn.readfile(edit_info.filepath)
    end

    if current_content then
      local hunks = InlineDiff.calculate_hunks(edit_info.original_content, current_content, 3)
      if #hunks > 0 then
        -- Get language for fenced code block
        local lang = edit_info.filepath and get_file_extension(edit_info.filepath) or "text"
        local line_ranges = calculate_line_ranges(hunks)
        for hunk_idx, hunk in ipairs(hunks) do
          local range = line_ranges[hunk_idx]
          local line_info = string.format("Lines %d-%d:", range.start_line, range.end_line)
          table.insert(lines, line_info)
          table.insert(lines, "")
          table.insert(lines, "```" .. lang)
          local code_content_start = #lines + 1
          local context_lines = 3
          local actual_context_before = {}
          local actual_context_after = {}

          -- Get context before from the NEW file
          local context_start = math.max(1, hunk.new_start - context_lines)
          for i = context_start, hunk.new_start - 1 do
            if current_content[i] then
              table.insert(actual_context_before, current_content[i])
            end
          end
          -- Get context after from the NEW file
          local context_end = math.min(#current_content, hunk.new_start + hunk.new_count + context_lines - 1)
          for i = hunk.new_start + hunk.new_count, context_end do
            if current_content[i] then
              table.insert(actual_context_after, current_content[i])
            end
          end
          for _, line in ipairs(actual_context_before) do
            table.insert(lines, line)
          end
          local new_lines_start = #lines + 1 -- Track where new lines start
          -- Add new lines (will be highlighted)
          for _, line in ipairs(hunk.new_lines) do
            table.insert(lines, line)
          end

          for _, line in ipairs(actual_context_after) do
            table.insert(lines, line)
          end
          table.insert(lines, "```")
          table.insert(lines, "")

          table.insert(diff_info, {
            start_line = code_content_start - 1, -- 0-based for extmarks
            end_line = #lines - 3, -- Exclude the closing ``` and empty line
            hunks = { hunk }, -- Single hunk for this section
            original_content = edit_info.original_content,
            current_content = current_content,
            language = lang,
            -- Point to where new_lines actually start in the buffer
            hunk_line_offset = new_lines_start - 1, -- 0-based, where highlighting should start
          })
        end
      else
        table.insert(lines, "*No changes detected*")
        table.insert(lines, "")
      end
    else
      table.insert(lines, "*Unable to read current content*")
      table.insert(lines, "")
    end
    table.insert(lines, "---")
    table.insert(lines, "")
    table.insert(file_sections, {
      key = key,
      edit_info = edit_info,
      start_line = section_start,
      end_line = #lines,
    })
  end

  return lines, file_sections, diff_info
end

---Apply highlights to the code sections only with corrected line mapping
---@param bufnr integer
---@param diff_info table[]
---@param ns_id integer
local function apply_markdown_diff_highlights(bufnr, diff_info, ns_id)
  local all_extmark_ids = {}

  for _, section in ipairs(diff_info) do
    -- For each section, we need to apply the inline diff logic
    -- but with the correct line offset for the markdown buffer
    local hunk = section.hunks[1] -- Single hunk per section
    local line_offset = section.hunk_line_offset

    log:debug("[SuperDiff] Applying highlights for hunk at line_offset %d", line_offset)

    -- Apply removed lines as virtual text
    if #hunk.old_lines > 0 then
      local attach_line = line_offset
      if attach_line < api.nvim_buf_line_count(bufnr) then
        local is_modification = #hunk.new_lines > 0
        local sign_hl = is_modification and "DiagnosticWarn" or "DiagnosticError"

        -- Create virtual text for ALL removed lines in this hunk
        local virt_lines = {}
        for _, old_line in ipairs(hunk.old_lines) do
          local display_line = old_line
          local padding = math.max(0, vim.o.columns - #display_line - 2)
          table.insert(virt_lines, { { display_line .. string.rep(" ", padding), "DiffDelete" } })
        end

        -- Single extmark for all removed lines in this hunk
        local extmark_id = api.nvim_buf_set_extmark(bufnr, ns_id, attach_line, 0, {
          virt_lines = virt_lines,
          virt_lines_above = true,
          priority = 100,
          sign_text = "▌",
          sign_hl_group = sign_hl,
        })
        table.insert(all_extmark_ids, extmark_id)
      end
    end

    -- Highlight new lines with corrected indexing
    for i = 1, #hunk.new_lines do
      local line_idx = line_offset + i - 1 -- Correct line mapping for markdown buffer
      if line_idx >= 0 and line_idx < api.nvim_buf_line_count(bufnr) then
        local is_modification = #hunk.old_lines > 0
        local sign_hl = is_modification and "DiagnosticWarn" or "DiagnosticOk"
        local extmark_id = api.nvim_buf_set_extmark(bufnr, ns_id, line_idx, 0, {
          line_hl_group = "DiffAdd",
          priority = 100,
          sign_text = "▌",
          sign_hl_group = sign_hl,
        })
        table.insert(all_extmark_ids, extmark_id)
        log:debug("[SuperDiff] Added green highlight at line %d", line_idx)
      end
    end
  end

  return all_extmark_ids
end

---Create and show the markdown super diff buffer
---@param chat CodeCompanion.Chat
function M.show_super_diff(chat)
  local tracked_edits = edit_tracker.get_tracked_edits(chat)
  if vim.tbl_isempty(tracked_edits) then
    vim.notify("No edits to show in this chat session", vim.log.levels.INFO)
    return
  end

  log:debug("[SuperDiff] Creating markdown super diff with %d files", vim.tbl_count(tracked_edits))

  local lines, file_sections, diff_info = generate_markdown_super_diff(tracked_edits)
  -- Create floating buffer with markdown filetype
  local ui = require("codecompanion.utils.ui")
  local bufnr, winnr = ui.create_float(lines, {
    filetype = "markdown", -- This will give us proper markdown rendering
    title = string.format("Super Diff - Chat %d (%d files)", chat.id, vim.tbl_count(tracked_edits)),
    window = {
      width = math.min(140, vim.o.columns - 10),
      height = math.min(50, vim.o.lines - 10),
      row = "center",
      col = "center",
    },
    relative = "editor",
    lock = true,
    ignore_keymaps = true,
  })
  vim.wo[winnr].number = true
  vim.wo[winnr].relativenumber = false

  -- Apply diff highlights to code sections
  local ns_id = api.nvim_create_namespace("codecompanion_super_diff")
  local extmark_ids = apply_markdown_diff_highlights(bufnr, diff_info, ns_id)
  M.setup_keymaps(bufnr, chat, file_sections, ns_id)
  vim.notify(string.format("Super diff: %d files", vim.tbl_count(tracked_edits)))
end

function M.setup_keymaps(bufnr, chat, file_sections, ns_id)
  local function cleanup()
    if api.nvim_buf_is_valid(bufnr) then
      api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    end
  end
  local function accept_all()
    cleanup()
    vim.notify("All changes accepted")
    api.nvim_buf_delete(bufnr, { force = true })
  end
  local function reject_all()
    for _, section in ipairs(file_sections) do
      local edit_info = section.edit_info
      if edit_info.type == "buffer" and edit_info.bufnr and api.nvim_buf_is_valid(edit_info.bufnr) then
        api.nvim_buf_set_lines(edit_info.bufnr, 0, -1, false, edit_info.original_content)
      elseif edit_info.filepath then
        vim.fn.writefile(edit_info.original_content, edit_info.filepath)
        local file_bufnr = vim.fn.bufnr(edit_info.filepath)
        if file_bufnr ~= -1 and api.nvim_buf_is_loaded(file_bufnr) then
          api.nvim_command("checktime " .. file_bufnr)
        end
      end
    end
    cleanup()
    vim.notify("All changes reverted")
    api.nvim_buf_delete(bufnr, { force = true })
  end
  vim.keymap.set("n", "ga", accept_all, { buffer = bufnr, desc = "Accept all changes" })
  vim.keymap.set("n", "gr", reject_all, { buffer = bufnr, desc = "Reject all changes" })
  vim.keymap.set("n", "q", function()
    cleanup()
    api.nvim_buf_delete(bufnr, { force = true })
  end, { buffer = bufnr, desc = "Close super diff" })
end

return M
