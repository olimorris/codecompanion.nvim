local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local path = require("plenary.path")
local symbol_utils = require("codecompanion.strategies.chat.helpers")
local util = require("codecompanion.utils")
local fmt = string.format

---Get quickfix list with type detection
---@return table[] entries Array of quickfix entries with has_diagnostic field
local function get_qflist_entries()
  local qflist = vim.fn.getqflist()
  local entries = {}
  for i, item in ipairs(qflist) do
    local filename = vim.fn.bufname(item.bufnr)
    if filename ~= "" then
      local text = item.text or ""
      local nr = item.nr or 0
      local has_diagnostic
      if nr == -1 then
        -- Search results: treat as files (show whole content)
        has_diagnostic = false
      else
        -- Detection: if text ends with the filename, it's a file entry
        -- If text is an error message that doesn't end with filename, it's lsp diagnostics
        local escaped_filename = vim.pesc(filename)
        local is_file_entry = text:match(escaped_filename .. "$") ~= nil
        has_diagnostic = not is_file_entry
      end
      table.insert(entries, {
        idx = i,
        filename = filename,
        lnum = item.lnum,
        text = text,
        type = item.type or "",
        nr = nr,
        has_diagnostic = has_diagnostic,
        display = fmt("%s:%d: %s", vim.fn.fnamemodify(filename, ":."), item.lnum, text),
      })
    end
  end

  return entries
end

---Extract symbols from a file using TreeSitter
---@param filepath string Path to the file
---@return table[]|nil symbols Array of symbols with start_line, end_line, name, kind
---@return string|nil content File content if successful
local function extract_file_symbols(filepath)
  -- Only include function/method/class symbols for quickfix
  local target_kinds = { "Function", "Method", "Class" }
  return symbol_utils.extract_file_symbols(filepath, target_kinds)
end

---Find which symbol contains a diagnostic line
---@param diagnostic_line number Line number of the diagnostic
---@param symbols table[] Array of symbols to search through
---@return table|nil symbol The smallest containing symbol or nil
local function find_containing_symbol(diagnostic_line, symbols)
  local best_symbol = nil
  local best_size = math.huge

  for _, symbol in ipairs(symbols) do
    if symbol.start_line <= diagnostic_line and symbol.end_line >= diagnostic_line then
      local symbol_size = symbol.end_line - symbol.start_line
      if symbol_size < best_size then
        best_symbol = symbol
        best_size = symbol_size
      end
    end
  end

  return best_symbol
end

---Group diagnostics by proximity (within 5 lines)
---@param diagnostics table[] Array of diagnostic entries
---@return table[] groups Array of diagnostic groups
local function group_by_proximity(diagnostics)
  if #diagnostics <= 1 then
    return { diagnostics }
  end
  -- Sort by line number
  table.sort(diagnostics, function(a, b)
    return a.lnum < b.lnum
  end)
  local groups = {}
  local current_group = { diagnostics[1] }
  for i = 2, #diagnostics do
    local prev_line = current_group[#current_group].lnum
    local curr_line = diagnostics[i].lnum
    if curr_line - prev_line <= 5 then
      -- Close enough, add to current group
      table.insert(current_group, diagnostics[i])
    else
      -- Too far, start new group
      table.insert(groups, current_group)
      current_group = { diagnostics[i] }
    end
  end
  table.insert(groups, current_group)

  return groups
end

---Group diagnostics by symbol they belong to
---@param filepath string Path to the file
---@param diagnostics table[] Array of diagnostic entries
---@param file_content? string Optional file content to avoid re-reading
---@return table[] diagnostic_groups Array of groups with diagnostics and symbol info
---@return string|nil content File content if available
local function group_diagnostics_by_symbol(filepath, diagnostics, file_content)
  local symbols, content = extract_file_symbols(filepath)
  -- Use provided file_content if available to avoid re-reading
  if not content and file_content then
    content = file_content
  end
  -- If no symbols found, fallback to proximity grouping
  if not symbols or #symbols == 0 then
    return group_by_proximity(diagnostics), content
  end
  -- Group diagnostics by which symbol contains them
  local symbol_groups = {}
  local ungrouped_diagnostics = {}
  for _, diagnostic in ipairs(diagnostics) do
    local containing_symbol = find_containing_symbol(diagnostic.lnum, symbols)
    if containing_symbol then
      local symbol_key =
        fmt("%s_%d_%d", containing_symbol.name, containing_symbol.start_line, containing_symbol.end_line)
      if not symbol_groups[symbol_key] then
        symbol_groups[symbol_key] = {
          symbol = containing_symbol,
          diagnostics = {},
        }
      end
      table.insert(symbol_groups[symbol_key].diagnostics, diagnostic)
    else
      -- Diagnostic not in any symbol
      table.insert(ungrouped_diagnostics, diagnostic)
    end
  end

  -- Convert to array format and sort diagnostics within each group
  local result_groups = {}
  for _, group_info in pairs(symbol_groups) do
    table.sort(group_info.diagnostics, function(a, b)
      return a.lnum < b.lnum
    end)
    table.insert(result_groups, {
      diagnostics = group_info.diagnostics,
      symbol = group_info.symbol,
    })
  end

  -- Handle ungrouped diagnostics with proximity grouping
  if #ungrouped_diagnostics > 0 then
    local ungrouped_groups = group_by_proximity(ungrouped_diagnostics)
    for _, group in ipairs(ungrouped_groups) do
      table.insert(result_groups, {
        diagnostics = group,
        symbol = nil,
      })
    end
  end

  return result_groups, content
end

---Generate context for a group of diagnostics
---@param group_info table Group containing diagnostics and symbol
---@param file_content string Content of the file
---@param group_index number Index of this group
---@param total_groups number Total number of groups
---@return string context Formatted context with line numbers
local function generate_context_for_group(group_info, file_content, group_index, total_groups)
  local lines = vim.split(file_content, "\n")
  local diagnostics = group_info.diagnostics
  local symbol = group_info.symbol
  local context_start, context_end, header
  if symbol then
    -- Use symbol boundaries with padding
    context_start = math.max(1, symbol.start_line - 3)
    context_end = math.min(#lines, symbol.end_line + 3)
    header = fmt("%s: %s (lines %d-%d)", symbol.kind, symbol.name, symbol.start_line, symbol.end_line)
  else
    -- Use line-based context around diagnostics
    local start_line = diagnostics[1].lnum
    local end_line = diagnostics[#diagnostics].lnum
    context_start = math.max(1, start_line - 5)
    context_end = math.min(#lines, end_line + 5)
    header = fmt("lines %d-%d", context_start, context_end)
  end

  -- Build context lines
  local context_lines = {}
  for i = context_start, context_end do
    table.insert(context_lines, fmt("%d: %s", i, lines[i]))
  end
  local context = table.concat(context_lines, "\n")
  -- Add group header if multiple groups
  if total_groups > 1 then
    context = fmt("--- Group %d (%s) ---\n%s", group_index, header, context)
  end

  return context
end

---@class CodeCompanion.SlashCommand.Qflist: CodeCompanion.SlashCommand
local SlashCommand = {}

---Create new quickfix slash command instance
---@param args CodeCompanion.SlashCommandArgs
---@return CodeCompanion.SlashCommand.Qflist
function SlashCommand.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
    opts = args.opts,
  }, { __index = SlashCommand })

  return self
end

---Execute the quickfix slash command
---@return nil
function SlashCommand:execute()
  if not config.can_send_code() and (self.config.opts and self.config.opts.contains_code) then
    return log:warn("Sending of code has been disabled")
  end
  local entries = get_qflist_entries()
  if #entries == 0 then
    return log:warn("Quickfix list is empty")
  end
  self:output_entries(entries)
end

---Group quickfix entries by filename
---@param entries table[] Array of quickfix entries
---@return table files Grouped files with diagnostics
local function group_entries_by_file(entries)
  local files = {}
  for _, entry in ipairs(entries) do
    if not files[entry.filename] then
      files[entry.filename] = { diagnostics = {}, has_diagnostics = false }
    end

    if entry.has_diagnostic then
      table.insert(files[entry.filename].diagnostics, {
        lnum = entry.lnum,
        text = entry.text,
        type = entry.type,
      })
      files[entry.filename].has_diagnostics = true
    end
  end
  return files
end

---Process a single file and generate description for chat
---@param filepath string Path to the file
---@param file_data table File data with diagnostics
---@return string|nil description Formatted description for chat or nil if failed
---@return string id Reference ID for the file
local function process_single_file(filepath, file_data)
  local relative_path = vim.fn.fnamemodify(filepath, ":.")
  local ft = vim.filetype.match({ filename = filepath })
  local id = "<quickfix>" .. relative_path .. "</quickfix>"
  -- Read file once
  local ok, file_content = pcall(function()
    return path.new(filepath):read()
  end)
  if not ok then
    log:warn("Could not read file: %s", filepath)
    return nil, id
  end
  local content, description
  if file_data.has_diagnostics then
    local lines = vim.split(file_content, "\n")
    -- Small file: show everything with simple diagnostic summary
    if #lines < 100 then
      content = file_content
      local diagnostic_summary = {}
      for _, diagnostic in ipairs(file_data.diagnostics) do
        table.insert(diagnostic_summary, fmt("Line %d: %s", diagnostic.lnum, diagnostic.text))
      end
      description = fmt(
        [[<attachment filepath="%s">Here is the content from the file with quickfix entries (small file, showing all content):
  
  %s
  
```%s
%s
```
  </attachment>]],
        relative_path,
        table.concat(diagnostic_summary, "\n"),
        ft,
        content
      )
    else
      -- Large file: use smart grouping and context extraction
      local diagnostic_groups, _ = group_diagnostics_by_symbol(filepath, file_data.diagnostics, file_content)
      -- Generate diagnostic summary with groups
      local diagnostic_summary = {}
      for group_idx, group_info in ipairs(diagnostic_groups) do
        if #diagnostic_groups > 1 then
          if group_info.symbol then
            table.insert(
              diagnostic_summary,
              fmt("## Group %d (%s: %s):", group_idx, group_info.symbol.kind, group_info.symbol.name)
            )
          else
            table.insert(diagnostic_summary, fmt("## Group %d:", group_idx))
          end
        end
        for _, diagnostic in ipairs(group_info.diagnostics) do
          table.insert(diagnostic_summary, fmt("Line %d: %s", diagnostic.lnum, diagnostic.text))
        end
        if #diagnostic_groups > 1 then
          table.insert(diagnostic_summary, "") -- Empty line between groups
        end
      end
      -- Generate context for each group
      local contexts = {}
      for i, group_info in ipairs(diagnostic_groups) do
        local group_context = generate_context_for_group(group_info, file_content, i, #diagnostic_groups)
        table.insert(contexts, group_context)
      end
      content = table.concat(contexts, "\n\n")

      description = fmt(
        [[<attachment filepath="%s">Here is the content from the file with quickfix entries:
  
  %s
  
```%s
%s
```
  </attachment>]],
        relative_path,
        table.concat(diagnostic_summary, "\n"),
        ft,
        content
      )
    end
  else
    -- File-only entries
    content = file_content
    description = fmt(
      [[<attachment filepath="%s">Here is the content from the file:
  
```%s
%s
```
  </attachment>]],
      relative_path,
      ft,
      content
    )
  end

  return description, id
end

---Output quickfix entries to chat
---@param entries table[] Array of quickfix entries
---@return nil
function SlashCommand:output_entries(entries)
  local files = group_entries_by_file(entries)

  -- Output each file
  for filepath, file_data in pairs(files) do
    local description, id = process_single_file(filepath, file_data)
    if description then
      self.Chat:add_message({
        role = config.constants.USER_ROLE,
        content = description,
      }, { reference = id, visible = false })

      self.Chat.references:add({
        id = id,
        path = filepath,
        source = "codecompanion.strategies.chat.slash_commands.qflist",
      })
    end
  end

  util.notify(fmt("Added %d file(s) from quickfix list to chat", vim.tbl_count(files)))
end

return SlashCommand
