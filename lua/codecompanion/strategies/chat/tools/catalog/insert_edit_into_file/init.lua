--[[
Main orchestration for the insert_edit_into_file tool

This tool enables LLMs to make deterministic file edits through function calling.
It supports various edit operations: standard replacements, replace-all, substring matching,
file boundaries (start/end), and complete file overwrites.

## Architecture Overview:

1. **Entry Point (insert_edit_into_file / edit_buffer)**:
   - Separates edits into substring vs block/line types
   - Applies changes only if all edits succeed (atomic operation)

2. **Edit Processing (process_edits_sequentially)**:
   - Handles substring edits in parallel (replaceAll with no newlines)
   - Processes block/line edits sequentially
   - Each edit sees the result of previous edits
   - Detects conflicting edits

3. **Matching (strategies module)**:
   - Tries multiple matching strategies with fallback
   - Exact match → Whitespace normalized → Block anchor
   - For replaceAll + no newlines: uses efficient substring matching
   - Returns confidence scores for match selection

4. **Error Handling (match_selector module)**:
   - Generates helpful error messages with context
   - Suggests fixes for common mistakes
   - Shows similar matches when exact match fails

## Key Features:
- Atomic operations: all edits succeed or none are applied
- Smart matching with multiple fallback strategies
- Substring mode for efficient token/keyword replacement (max 1000)
- Handles whitespace differences and indentation variations
- Size limits: 2MB file, 50KB search text

## Special Cases:
- Empty files: oldText="" for initial content
- File boundaries: oldText="^" (start) or "$" (end)
- Deletions: newText=""
- Complete replacement: mode="overwrite"
--]]

local Path = require("plenary.path")

local codecompanion = require("codecompanion")
local config = require("codecompanion.config")
local constants = require("codecompanion.strategies.chat.tools.catalog.insert_edit_into_file.constants")
local diff = require("codecompanion.strategies.chat.helpers.diff")
local helpers = require("codecompanion.strategies.chat.helpers")
local match_selector = require("codecompanion.strategies.chat.tools.catalog.insert_edit_into_file.match_selector")
local strategies = require("codecompanion.strategies.chat.tools.catalog.insert_edit_into_file.strategies")
local wait = require("codecompanion.strategies.chat.helpers.wait")

local buffers = require("codecompanion.utils.buffers")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")
local utils = require("codecompanion.utils")

local api = vim.api
local fmt = string.format

---Load prompt from markdown file
---@return string The prompt content
local function load_prompt()
  local source_path = debug.getinfo(1, "S").source:sub(2)
  local dir = vim.fn.fnamemodify(source_path, ":h")
  local prompt_path = Path:new(dir, "prompt.md")
  return prompt_path:read()
end

local PROMPT = load_prompt()

-- Enhanced Python-like parser for handling LLM's mixed Python/JSON syntax
---@param edits string The string containing edits in Python-like format
---@return string The converted JSON-like string
local function parse_python_like_edits(edits)
  -- Fix booleans before quote conversion to prevent 'True' → "True" string conversion
  local fixed = edits
  -- Capture trailing delimiters ([,%]}%s]) to preserve structure
  fixed = fixed:gsub(":%s*True([,%]}%s])", ": true%1")
  fixed = fixed:gsub(":%s*False([,%]}%s])", ": false%1")
  fixed = fixed:gsub("^%s*True([,%]}%s])", "true%1")
  fixed = fixed:gsub("^%s*False([,%]}%s])", "false%1")
  fixed = fixed:gsub(":%s*True$", ": true")
  fixed = fixed:gsub(":%s*False$", ": false")

  -- LLMs often double-escape: convert \\n to actual newline character
  fixed = fixed:gsub("\\\\n", "\n")
  fixed = fixed:gsub("\\\\t", "\t")
  fixed = fixed:gsub("\\\\r", "\r")
  fixed = fixed:gsub("\\\\\\\\", "\\")

  -- Convert Python-style single quotes to JSON double quotes while preserving escaped quotes
  local result = {}
  local i = 1
  local in_string = false
  local escape_next = false

  while i <= #fixed do
    local char = fixed:sub(i, i)

    if escape_next then
      -- Previous character was backslash
      if char == "'" and in_string then
        -- Escaped single quote inside string - convert to literal single quote
        table.insert(result, "'")
      else
        -- Other escaped character - keep as-is
        table.insert(result, char)
      end
      escape_next = false
    elseif char == "\\" and in_string then
      -- Escape character in string - check what's being escaped
      local next_char = fixed:sub(i + 1, i + 1)
      if next_char == "'" then
        -- This is escaping a single quote, we'll handle it in next iteration
        escape_next = true
      else
        -- Other escape sequence, keep the backslash
        table.insert(result, char)
      end
    elseif char == '"' and in_string then
      -- Double quote inside a single-quoted string - escape it
      table.insert(result, '\\"')
    elseif char == "'" and not in_string then
      -- Starting a string, convert to double quote
      table.insert(result, '"')
      in_string = true
    elseif char == "'" and in_string then
      -- Ending a string, convert to double quote
      table.insert(result, '"')
      in_string = false
    else
      -- Regular character
      table.insert(result, char)
    end

    i = i + 1
  end

  return table.concat(result)
end

---Fix edits field if it's a string instead of a table (handles LLM JSON formatting issues)
---@param args table The arguments containing edits to fix
---@return table|nil, string|nil The fixed arguments and error message
local function fix_edits_if_needed(args)
  -- Only do work if there's actually a problem - zero overhead for good JSON
  if type(args.edits) == "table" then
    return args, nil
  end

  if type(args.edits) ~= "string" then
    return nil, "edits must be an array or parseable string"
  end

  -- First, try standard JSON parsing
  local success, parsed_edits = pcall(vim.json.decode, args.edits)

  if success and type(parsed_edits) == "table" then
    args.edits = parsed_edits
    return args, nil
  end

  -- If that failed, try minimal fixes for common LLM JSON issues
  local fixed_json = args.edits

  -- Convert Python dict syntax to JSON object syntax
  fixed_json = fixed_json:gsub("{'oldText':", '{"oldText":')
  fixed_json = fixed_json:gsub("'newText':", '"newText":')
  fixed_json = fixed_json:gsub("'replaceAll':", '"replaceAll":')

  -- Convert single quotes to double quotes for values
  fixed_json = fixed_json:gsub(": '([^']*)'", ': "%1"')
  fixed_json = fixed_json:gsub(", '([^']*)'", ', "%1"')

  -- Capture delimiters ([,}%]]) to preserve array/object structure
  fixed_json = fixed_json:gsub(": False([,}%]])", ": false%1")
  fixed_json = fixed_json:gsub(": True([,}%]])", ": true%1")

  -- Try parsing the fixed JSON
  success, parsed_edits = pcall(vim.json.decode, fixed_json)

  if success and type(parsed_edits) == "table" then
    args.edits = parsed_edits
    return args, nil
  end

  -- FALLBACK: Try enhanced Python-like parser
  local python_converted = parse_python_like_edits(args.edits)
  if python_converted then
    success, parsed_edits = pcall(vim.json.decode, python_converted)
    if success and type(parsed_edits) == "table" then
      args.edits = parsed_edits
      return args, nil
    end
  end

  -- If all else fails, provide helpful error
  return nil, fmt("Could not parse edits as JSON. Original: %s", args.edits:sub(1, 200))
end

-- Read file content safely
---@param path string
---@return string|nil, string|nil, table|nil The content, error, and file info
local function read_file_content(path)
  local p = Path:new(path)
  if not p:exists() or not p:is_file() then
    return nil, fmt("File does not exist or is not a file: `%s`", path)
  end

  local stat = vim.uv.fs_stat(path)
  local mtime = stat and stat.mtime.sec or nil
  local content = p:read()
  if not content then
    return nil, fmt("Could not read file content: `%s`", path)
  end

  -- Track file metadata for proper handling
  local file_info = {
    has_trailing_newline = content:match("\n$") ~= nil,
    is_empty = content == "",
    mtime = mtime,
  }

  return content, nil, file_info
end

-- Write file content
---@param path string
---@param content string
---@param file_info table|nil
---@return boolean, string|nil Success status and error message
local function write_file_content(path, content, file_info)
  file_info = file_info or {}

  -- Check if file was modified since we read it
  if file_info.mtime then
    local stat = vim.uv.fs_stat(path)
    if stat and stat.mtime.sec ~= file_info.mtime then
      return false,
        fmt(
          "File was modified by another process since it was read (expected mtime: %d, actual: %d)",
          file_info.mtime,
          stat.mtime.sec
        )
    end
  end

  -- Preserve original newline behavior
  if file_info.has_trailing_newline == false and content:match("\n$") then
    content = content:gsub("\n$", "")
  elseif file_info.has_trailing_newline == true and not content:match("\n$") then
    content = content .. "\n"
  end

  local p = Path:new(path)
  local ok, err = pcall(function()
    p:write(content, "w")
  end)

  if not ok then
    return false, fmt("Failed to write file: `%s`", err)
  end

  -- Refresh buffer if file is open
  local bufnr = vim.fn.bufnr(p.filename)
  if bufnr ~= -1 and api.nvim_buf_is_loaded(bufnr) then
    api.nvim_command("checktime " .. bufnr)
  end

  return true, nil
end

---Separate edits into substring replaceAll and other types
---@param edits table[] Array of all edit operations
---@return table[], table[] (with original indices preserved)
local function separate_edits_by_type(edits)
  local substring_edits = {}
  local other_edits = {}

  for i, edit in ipairs(edits) do
    -- Substring edits are: replaceAll=true AND single-line (no newlines in oldText)
    if edit.replaceAll and edit.oldText and not edit.oldText:find("\n") then
      table.insert(substring_edits, { edit = edit, original_index = i })
    else
      table.insert(other_edits, { edit = edit, original_index = i })
    end
  end

  return substring_edits, other_edits
end

---Extract explanation from action (top level or fallback to first edit)
---@param action table The action containing explanation
---@return string Formatted explanation with newline prefix, or empty string
local function extract_explanation(action)
  local explanation = action.explanation or (action.edits and action.edits[1] and action.edits[1].explanation)

  if explanation and explanation ~= "" then
    return "\n" .. explanation
  end

  return ""
end

---Process substring replaceAll edits in parallel to avoid overlaps
---Finds all matches in original content, then applies all replacements at once
---@param content string The original content
---@param substring_edits table[] Array of substring replaceAll edits
---@return string|nil The content with all replacements applied, or nil on error
---@return string|nil Error message if processing failed
local function process_substring_edits_parallel(content, substring_edits)
  -- Collect all matches from original content
  local all_replacements = {}

  for i, edit in ipairs(substring_edits) do
    -- Find all matches in ORIGINAL content
    local matches = strategies.substring_exact_match(content, edit.oldText)

    if #matches == 0 then
      return nil, fmt("Substring edit %d: pattern '%s' not found in file", i, edit.oldText)
    end

    -- Store all replacements with their positions
    for _, match in ipairs(matches) do
      table.insert(all_replacements, {
        start_pos = match.start_pos,
        end_pos = match.end_pos,
        old_text = edit.oldText,
        new_text = edit.newText,
        edit_index = i,
      })
    end
  end

  -- Sort replacements by position (descending) to maintain positions during replacement
  table.sort(all_replacements, function(a, b)
    return a.start_pos > b.start_pos
  end)

  -- Apply all replacements from end to start
  local result_content = content
  for _, replacement in ipairs(all_replacements) do
    local before = result_content:sub(1, replacement.start_pos - 1)
    local after = result_content:sub(replacement.end_pos + 1)
    result_content = before .. replacement.new_text .. after
  end

  return result_content, nil
end

---Apply substring edits in parallel and record results
---@param content string The current content
---@param substring_edits table[] Array of substring edit wrappers
---@return string|nil new_content, table|nil error_result
local function apply_substring_edits(content, substring_edits)
  local substring_edit_list = vim.tbl_map(function(item)
    return item.edit
  end, substring_edits)

  local parallel_result, parallel_error = process_substring_edits_parallel(content, substring_edit_list)

  if parallel_error then
    return nil,
      {
        success = false,
        error = "substring_parallel_processing_failed",
        message = parallel_error,
      }
  end

  return parallel_result, nil
end

---Create result entries for substring edits
---@param substring_edits table[] Array of substring edit wrappers
---@return table[] results, table[] strategies
local function create_substring_results(substring_edits)
  local results = {}
  local match_strategies = {}

  for _, item in ipairs(substring_edits) do
    table.insert(results, {
      edit_index = item.original_index,
      strategy = "substring_exact_match_parallel",
      confidence = 1.0,
      selection_reason = "parallel_processing",
      auto_selected = true,
    })
    table.insert(match_strategies, "substring_exact_match_parallel")
  end

  return results, match_strategies
end

---Handle special cases (empty file, overwrite mode)
---@param content string The current content
---@param edits table[] Array of edits
---@param options table Processing options
---@return table|nil result if special case handled, nil otherwise
local function handle_special_cases(content, edits, options)
  -- Handle empty file case
  if content == "" and #edits == 1 and (edits[1].oldText == "" or edits[1].oldText == nil) then
    return {
      success = true,
      final_content = edits[1].newText,
      edit_results = {
        {
          edit_index = 1,
          strategy = "empty_file_append",
          confidence = 1.0,
          selection_reason = "empty_file",
          auto_selected = true,
        },
      },
      strategies_used = { "empty_file_append" },
    }
  end

  -- Handle overwrite mode
  if options.mode == "overwrite" and #edits >= 1 then
    return {
      success = true,
      final_content = edits[1].newText,
      edit_results = {
        {
          edit_index = 1,
          strategy = "overwrite_mode",
          confidence = 1.0,
          selection_reason = "overwrite_mode",
          auto_selected = true,
        },
      },
      strategies_used = { "overwrite_mode" },
    }
  end

  return nil
end

---Check for conflicting edits
---@param content string The current content
---@param edits table[] Array of edits
---@param options table Processing options
---@return table|nil error_result if conflicts found, nil otherwise
local function check_for_conflicts(content, edits, options)
  if not options.dry_run then
    local conflicts = match_selector.detect_edit_conflicts(content, edits)
    if #conflicts > 0 then
      return {
        success = false,
        error = "conflicting_edits",
        conflicts = conflicts,
        conflict_descriptions = vim.tbl_map(function(c)
          return c.description
        end, conflicts),
      }
    end
  end
  return nil
end

---Validate required fields for a single edit
---@param edit table The edit to validate
---@param index number Edit index for error messages
---@param content string Current content
---@param options table Processing options
---@param partial_results table[] Results from previous edits
---@return table|nil error_result if validation fails, nil otherwise
local function validate_edit_fields(edit, index, content, options, partial_results)
  if not edit.oldText and not (content == "" or options.mode == "overwrite") then
    return {
      success = false,
      failed_at_edit = index,
      error = "missing_oldText",
      partial_results = partial_results,
      message = "Edit #"
        .. index
        .. " is missing required field 'oldText'. Every edit MUST have both 'oldText' and 'newText' fields.",
    }
  end

  if not edit.newText and edit.newText ~= "" then
    return {
      success = false,
      failed_at_edit = index,
      error = "missing_newText",
      partial_results = partial_results,
      message = "Edit #"
        .. index
        .. " is missing required field 'newText'. Every edit MUST have both 'oldText' and 'newText' fields.",
    }
  end

  return nil
end

---Process a single edit operation
---@param edit table The edit to process
---@param index number Edit index
---@param content string Current content
---@param options table Processing options
---@param partial_results table[] Results from previous edits
---@return string|nil new_content, table|nil error_result, table|nil result_info
local function process_single_edit(edit, index, content, options, partial_results)
  local validation_error = validate_edit_fields(edit, index, content, options, partial_results)
  if validation_error then
    return nil, validation_error, nil
  end

  -- Find matches using strategies
  local match_result = strategies.find_best_match(content, edit.oldText, edit.replaceAll)

  if not match_result.success then
    return nil,
      {
        success = false,
        failed_at_edit = index,
        error = match_result.error,
        partial_results = partial_results,
        attempted_strategies = match_result.attempted_strategies,
      },
      nil
  end

  local selection_result = strategies.select_best_match(match_result.matches, edit.replaceAll)

  if not selection_result.success then
    return nil,
      {
        success = false,
        failed_at_edit = index,
        error = selection_result.error,
        matches = selection_result.matches,
        suggestion = selection_result.suggestion,
        partial_results = partial_results,
      },
      nil
  end

  -- Apply the replacement
  local new_content = strategies.apply_replacement(content, selection_result.selected, edit.newText)

  local result_info = {
    edit_index = index,
    strategy = match_result.strategy_used,
    confidence = selection_result.selected.confidence
      or (type(selection_result.selected) == "table" and selection_result.selected[1] and selection_result.selected[1].confidence)
      or 0,
    selection_reason = selection_result.selection_reason,
    auto_selected = selection_result.auto_selected,
  }

  return new_content, nil, result_info
end

---Process multiple edits sequentially
---@param content string The current file content
---@param edits table[] The array of edits
---@param options table|nil Options for processing
---@return table Result containing success status and final content
local function process_edits_sequentially(content, edits, options)
  options = options or {}
  local current_content = content
  local results = {}
  local strategies_used = {}

  -- Step 1: Separate edits by type (substring vs block/single)
  local substring_edits, other_edits = separate_edits_by_type(edits)

  -- Step 2: Process all substring replaceAll edits in parallel (if any)
  if #substring_edits > 0 then
    local new_content, error_result = apply_substring_edits(current_content, substring_edits)
    if error_result then
      return error_result
    end

    current_content = new_content --[[@as string]]
    local substring_results, substring_strategies = create_substring_results(substring_edits)
    vim.list_extend(results, substring_results)
    vim.list_extend(strategies_used, substring_strategies)

    log:debug("[Insert Edit Into File::Main] Applied %d substring edits in parallel", #substring_edits)
  end

  -- Step 3: Extract block/single edits for special case and conflict checking
  local block_edits = vim.tbl_map(function(item)
    return item.edit
  end, other_edits)

  -- Special cases (empty file, overwrite mode)
  local special_result = handle_special_cases(current_content, block_edits, options)
  if special_result then
    return special_result
  end

  local conflict_result = check_for_conflicts(current_content, block_edits, options)
  if conflict_result then
    return conflict_result
  end

  -- Process each block/single edit sequentially
  for i, edit_wrapper in ipairs(other_edits) do
    local edit = edit_wrapper.edit
    local original_index = edit_wrapper.original_index
    local new_content, error_result, result_info =
      process_single_edit(edit, original_index, current_content, options, results)

    if error_result then
      return error_result
    end

    current_content = new_content--[[@as string]]
    table.insert(results, result_info)
    ---@diagnostic disable-next-line: need-check-nil
    table.insert(strategies_used, result_info.strategy)
  end

  return {
    success = true,
    final_content = current_content,
    edit_results = results,
    strategies_used = strategies_used,
  }
end

-- Main edit function for files
---@param action table
---@param chat_bufnr number
---@param output_handler function
---@param opts table|nil
local function edit_file(action, chat_bufnr, output_handler, opts)
  opts = opts or {}
  local path = helpers.validate_and_normalize_path(action.filepath)

  if not path then
    return output_handler({
      status = "error",
      data = fmt("Error: Invalid or non-existent filepath `%s`", action.filepath),
    })
  end

  -- Read current file content
  local current_content, read_err, file_info = read_file_content(path)
  if not current_content then
    return output_handler({
      status = "error",
      data = read_err,
    })
  end

  -- Handle case where LLM sends edits as stringified JSON
  if type(action.edits) == "string" then
    local ok, parsed = pcall(vim.json.decode, action.edits)
    if ok and type(parsed) == "table" then
      action.edits = parsed
    end
  end

  -- Early size validation to prevent freezes
  if #current_content > constants.LIMITS.FILE_SIZE_MAX then
    return output_handler({
      status = "error",
      data = fmt(
        "Error: File too large (%d bytes). Maximum supported size is %d bytes.",
        #current_content,
        constants.LIMITS.FILE_SIZE_MAX
      ),
    })
  end

  -- Process edits with dry run first
  local dry_run_result = process_edits_sequentially(current_content, action.edits, {
    dry_run = true,
    path = path,
    file_info = file_info,
    mode = action.mode,
  })

  if not dry_run_result.success then
    local error_message = match_selector.format_helpful_error(dry_run_result, action.edits)
    return output_handler({
      status = "error",
      data = error_message,
    })
  end

  -- Generate summary for diffs
  local strategies_summary = table.concat(
    vim.tbl_map(function(strategy)
      return strategy:gsub("_", " ")
    end, dry_run_result.strategies_used),
    ", "
  )

  if action.dryRun then
    local ok, edit_word = pcall(utils.pluralize, #action.edits, "edit")
    if not ok then
      edit_word = "edit(s)"
    end
    return output_handler({
      status = "success",
      data = fmt(
        "DRY RUN - Successfully processed %d %s using strategies: %s\nFile: `%s`\n\nTo apply these changes, set 'dryRun': false",
        #action.edits,
        edit_word,
        strategies_summary,
        action.filepath
      ),
    })
  end

  -- Write to DISK before creating diff
  local write_ok, write_err = write_file_content(path, dry_run_result.final_content, file_info)
  if not write_ok then
    return output_handler({
      status = "error",
      data = fmt("Error writing to `%s`: %s", action.filepath, write_err),
    })
  end

  -- Auto-apply in YOLO mode
  if vim.g.codecompanion_yolo_mode then
    return output_handler({
      status = "success",
      data = fmt("Edited `%s` file%s", action.filepath, extract_explanation(action)),
    })
  end

  -- Create diff for user approval
  local diff_id = math.random(10000000)
  local original_lines = vim.split(current_content, "\n", { plain = true })
  local should_diff = diff.create(path, diff_id, {
    original_content = original_lines,
  })

  local final_success = {
    status = "success",
    data = fmt("Edited `%s` file%s", action.filepath, extract_explanation(action)),
  }

  if should_diff and opts.user_confirmation then
    local accept = config.strategies.inline.keymaps.accept_change.modes.n
    local reject = config.strategies.inline.keymaps.reject_change.modes.n

    local wait_opts = {
      chat_bufnr = chat_bufnr,
      notify = config.display.icons.warning .. " Waiting for decision ...",
      sub_text = fmt("`%s` - Accept edits / `%s` - Reject edits", accept, reject),
    }

    return wait.for_decision(diff_id, { "CodeCompanionDiffAccepted", "CodeCompanionDiffRejected" }, function(result)
      local response
      if result.accepted then
        -- File is already written to disk
        response = final_success
      else
        -- User rejected - restore original content - Skip mtime check since we own it
        local restore_file_info = {
          has_trailing_newline = file_info and file_info.has_trailing_newline,
          is_empty = file_info and file_info.is_empty,
        }
        local restore_ok, restore_err = write_file_content(path, current_content, restore_file_info)
        if not restore_ok then
          log:error("Failed to restore original content: %s", restore_err)
          -- Inform user about restoration failure
          response = {
            status = "error",
            data = fmt(
              "User rejected the edits for `%s`, but failed to restore original content: %s\n\nWARNING: File may be in an inconsistent state. Please review and restore manually if needed.",
              action.filepath,
              restore_err
            ),
          }
        else
          if result.timeout and should_diff and should_diff.reject then
            should_diff:reject()
          end
          response = {
            status = "error",
            data = (result.timeout and "User failed to accept the edits in time" or "User rejected the edits")
              .. fmt(" for `%s`", action.filepath),
          }
        end
      end

      codecompanion.restore(chat_bufnr)
      return output_handler(response)
    end, wait_opts)
  else
    -- File is already written above, no need for user confirmation
    return output_handler(final_success)
  end
end

-- Main edit function for buffers
---@param bufnr number
---@param chat_bufnr number
---@param action table
---@param output_handler function
---@param opts table|nil
local function edit_buffer(bufnr, chat_bufnr, action, output_handler, opts)
  opts = opts or {}
  local diff_id = math.random(10000000)

  -- NOTE: Ensure the buffer is loaded before accessing its contents.
  -- This addresses an issue with snacks.nvim, which may leave buffers unloaded when opening multiple files.
  if not api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
  end

  -- Get current buffer content
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local current_content = table.concat(lines, "\n")
  local original_content = vim.deepcopy(lines)

  -- Track buffer metadata
  local file_info = {
    has_trailing_newline = current_content:match("\n$") ~= nil,
    is_empty = current_content == "",
  }

  -- Handle case where LLM sends edits as stringified JSON
  if type(action.edits) == "string" then
    local ok, parsed = pcall(vim.json.decode, action.edits)
    if ok and type(parsed) == "table" then
      action.edits = parsed
    end
  end

  -- Process edits with dry run
  local dry_run_result = process_edits_sequentially(current_content, action.edits, {
    dry_run = true,
    buffer = bufnr,
    file_info = file_info,
    mode = action.mode,
  })

  local buffer_name = api.nvim_buf_get_name(bufnr)
  local display_name = buffer_name ~= "" and vim.fn.fnamemodify(buffer_name, ":.") or fmt("buffer %d", bufnr)

  if not dry_run_result.success then
    local error_message = match_selector.format_helpful_error(dry_run_result, action.edits)
    return output_handler({
      status = "error",
      data = fmt("Error processing edits for `%s`:\n%s", display_name, error_message),
    })
  end

  -- Generate summary
  local strategies_summary = table.concat(
    vim.tbl_map(function(strategy)
      return strategy:gsub("_", " ")
    end, dry_run_result.strategies_used),
    ", "
  )

  if action.dryRun then
    local ok, edit_word = pcall(utils.pluralize, #action.edits, "edit")
    if not ok then
      edit_word = "edit(s)"
    end
    return output_handler({
      status = "success",
      data = fmt(
        "DRY RUN - Successfully processed %d %s using strategies: %s\nBuffer: `%s`\n\nTo apply these changes, set 'dryRun': false",
        #action.edits,
        edit_word,
        strategies_summary,
        display_name
      ),
    })
  end

  -- Apply changes to buffer
  local final_lines = vim.split(dry_run_result.final_content, "\n", { plain = true })
  api.nvim_buf_set_lines(bufnr, 0, -1, false, final_lines)

  local should_diff = diff.create(bufnr, diff_id, {
    original_content = original_content,
  })

  -- Find scroll position
  local start_line = nil
  if dry_run_result.edit_results[1] and dry_run_result.edit_results[1].start_line then
    start_line = dry_run_result.edit_results[1].start_line
  end

  if start_line then
    ui.scroll_to_line(bufnr, start_line)
  end

  -- Auto-save if in YOLO mode
  if vim.g.codecompanion_yolo_mode then
    api.nvim_buf_call(bufnr, function()
      vim.cmd("silent write")
    end)
  end

  local success = {
    status = "success",
    data = fmt("Edited `%s` buffer%s", display_name, extract_explanation(action)),
  }

  if should_diff and opts.user_confirmation then
    local accept = config.strategies.inline.keymaps.accept_change.modes.n
    local reject = config.strategies.inline.keymaps.reject_change.modes.n

    local wait_opts = {
      chat_bufnr = chat_bufnr,
      notify = config.display.icons.warning .. " Waiting for diff approval ...",
      sub_text = fmt("`%s` - Accept edits / `%s` - Reject edits", accept, reject),
    }

    return wait.for_decision(diff_id, { "CodeCompanionDiffAccepted", "CodeCompanionDiffRejected" }, function(result)
      local response
      if result.accepted then
        pcall(function()
          api.nvim_buf_call(bufnr, function()
            vim.cmd("silent! w")
          end)
        end)
        response = success
      else
        if result.timeout and should_diff and should_diff.reject then
          should_diff:reject()
        end
        response = {
          status = "error",
          data = (result.timeout and "User failed to accept the edits in time" or "User rejected the edits")
            .. fmt(" for `%s`", display_name),
        }
      end

      codecompanion.restore(chat_bufnr)
      return output_handler(response)
    end, wait_opts)
  else
    return output_handler(success)
  end
end

---@class CodeCompanion.Tool.EditFile: CodeCompanion.Tools.Tool
return {
  name = "insert_edit_into_file",
  cmds = {
    ---Execute the experimental edit tool commands
    ---@param self CodeCompanion.Tools
    ---@param args table The arguments from the LLM's tool call
    ---@param input? any The output from the previous function call
    ---@param output_handler function Async callback for completion
    ---@return nil|table
    function(self, args, input, output_handler)
      -- Only check edits if we need to - zero overhead for good JSON
      if args.edits then
        local fixed_args, error_msg = fix_edits_if_needed(args)
        if not fixed_args then
          return output_handler({
            status = "error",
            data = fmt("Invalid edits format: %s", error_msg),
          })
        end
        args = fixed_args
      end

      -- Check if file is currently open in buffer
      local bufnr = buffers.get_bufnr_from_path(args.filepath)
      if bufnr then
        return edit_buffer(bufnr, self.chat.bufnr, args, output_handler, self.tool.opts)
      else
        return edit_file(args, self.chat.bufnr, output_handler, self.tool.opts)
      end
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "insert_edit_into_file",
      description = PROMPT,
      parameters = {
        type = "object",
        properties = {
          filepath = {
            type = "string",
            description = "The path to the file to edit, including its filename and extension",
          },
          edits = {
            type = "array",
            description = "Array of edit operations to perform sequentially",
            items = {
              type = "object",
              properties = {
                oldText = {
                  type = "string",
                  description = "Exact text to find and replace. Include enough surrounding context (like function signatures, variable names) to make it unique in the file.",
                },
                newText = {
                  type = "string",
                  description = "Text to replace the oldText with",
                },
                replaceAll = {
                  type = "boolean",
                  default = false,
                  description = "Replace all occurrences of oldText. If false and multiple matches are found, the system will try to automatically select the best match or ask for clarification.",
                },
              },
              required = { "oldText", "newText", "replaceAll" },
              additionalProperties = false,
            },
          },
          dryRun = {
            type = "boolean",
            default = false,
            description = "When true, validates edits and shows what would be changed without applying them. Only use when explicitly requested.",
          },
          mode = {
            type = "string",
            enum = { "append", "overwrite" },
            default = "append",
            description = "append: normal edit behavior, overwrite: replace entire file content with newText from first edit",
          },
          explanation = {
            type = "string",
            description = "Brief explanation of what the edits accomplish",
          },
        },
        required = { "filepath", "edits", "explanation", "mode", "dryRun" },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  system_prompt = [[- Always use insert_edit_into_file to modify existing files by providing exact oldText to match and newText to replace it.
- Include enough surrounding context in oldText to make matches unique and unambiguous. All edits are atomic: either all succeed or none are applied.]],
  handlers = {
    ---The handler to determine whether to prompt the user for approval
    ---@param self CodeCompanion.Tool.EditFile
    ---@param tools CodeCompanion.Tools
    ---@return boolean
    prompt_condition = function(self, tools)
      local args = self.args
      local bufnr = buffers.get_bufnr_from_path(args.filepath)
      if bufnr then
        if self.opts.require_approval_before and self.opts.require_approval_before.buffer then
          return true
        end
        return false
      end

      if self.opts.require_approval_before and self.opts.require_approval_before.file then
        return true
      end
      return false
    end,

    ---@param tools CodeCompanion.Tools The tool object
    ---@return nil
    on_exit = function(tools) end,
  },
  output = {
    ---@param self CodeCompanion.Tool.EditFile
    ---@param tools CodeCompanion.Tools
    ---@return nil|string
    prompt = function(self, tools)
      local args = self.args
      local filepath = vim.fn.fnamemodify(args.filepath, ":.")
      local edit_count = args.edits and #args.edits or 0
      return fmt("Apply %d edit(s) to `%s`?", edit_count, filepath)
    end,

    ---@param self CodeCompanion.Tool.EditFile
    ---@param tool CodeCompanion.Tools
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, tool, cmd, stdout)
      local chat = tool.chat
      local llm_output = vim.iter(stdout):flatten():join("\n")
      chat:add_tool_output(self, llm_output)
    end,

    ---@param self CodeCompanion.Tool.EditFile
    ---@param tool CodeCompanion.Tools
    ---@param cmd table
    ---@param stderr table The error output from the command
    error = function(self, tool, cmd, stderr)
      local chat = tool.chat
      local errors = vim.iter(stderr):flatten():join("\n")
      chat:add_tool_output(self, "**Error:**\n" .. errors)
    end,
  },
}
