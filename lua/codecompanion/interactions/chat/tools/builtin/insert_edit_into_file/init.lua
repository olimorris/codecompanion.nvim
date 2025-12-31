--[[
Main orchestration for the insert_edit_into_file tool

This tool enables LLMs to make deterministic file edits through function calling.
It supports various edit operations: standard replacements, replace-all, substring matching,
file boundaries (start/end), and complete file overwrites.

## Architecture Overview:

1. **Entry Point (insert_edit_into_file / edit_buffer)**:
   - Separates edits into substring vs block/line types
   - Applies changes only if all edits succeed (atomic operation)

2. **Edit Processing (process_edits)**:
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

local Approvals = require("codecompanion.interactions.chat.tools.approvals")
local Constants = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.constants")
local config = require("codecompanion.config")
local helpers = require("codecompanion.interactions.chat.helpers")
local match_selector = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.match_selector")
local strategies = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.strategies")
local wait = require("codecompanion.interactions.chat.helpers.wait")

local buffers = require("codecompanion.utils.buffers")
local log = require("codecompanion.utils.log")
local ui_utils = require("codecompanion.utils.ui")
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

---Create response for output_handler
---@param status "success"|"error"
---@param msg string
---@return table
local function mk_response(status, msg)
  return { status = status, data = msg }
end

---Prompt user for rejection reason
---@param callback function
local function get_rejection_reason(callback)
  ui_utils.input({ prompt = "Rejection reason" }, function(input)
    callback(input or "")
  end)
end

---Write file content to disk
---@param path string
---@param content string
---@param info table|nil
---@return boolean, string|nil
local function write_file(path, content, info)
  info = info or {}

  -- Check for concurrent modifications
  if info.mtime then
    local stat = vim.uv.fs_stat(path)
    if stat and stat.mtime.sec ~= info.mtime then
      return false, fmt("File modified by another process (expected mtime: %d, actual: %d)", info.mtime, stat.mtime.sec)
    end
  end

  -- Preserve trailing newline behavior
  if info.has_trailing_newline == false and content:match("\n$") then
    content = content:gsub("\n$", "")
  elseif info.has_trailing_newline == true and not content:match("\n$") then
    content = content .. "\n"
  end

  local p = Path:new(path)
  local ok, err = pcall(function()
    p:write(content, "w")
  end)

  if not ok then
    return false, fmt("Failed to write file: `%s`", err)
  end

  -- Reload buffer if loaded
  local bufnr = vim.fn.bufnr(p.filename)
  if bufnr ~= -1 and api.nvim_buf_is_loaded(bufnr) then
    api.nvim_command("checktime " .. bufnr)
  end

  return true, nil
end

---Handle user decision for diff approval
---@param opts table { diff_id, chat_bufnr, name, success_msg, output_handler, bufnr?, on_reject? }
---@return any
local function handle_approval(opts)
  local wait_opts = {
    chat_bufnr = opts.chat_bufnr,
    notify = config.display.icons.warning .. " Waiting for diff approval ...",
    sub_text = "Review changes in the diff window",
  }

  return wait.for_decision(opts.diff_id, { "CodeCompanionDiffAccepted", "CodeCompanionDiffRejected" }, function(result)
    if result.accepted then
      if opts.bufnr then
        pcall(function()
          api.nvim_buf_call(opts.bufnr, function()
            vim.cmd("silent! w")
          end)
        end)
      end
      return opts.output_handler(mk_response("success", opts.success_msg))
    end

    get_rejection_reason(function(reason)
      local msg
      if result.timeout then
        msg = "User failed to accept the edits in time"
      else
        msg = fmt('User rejected the edits for `%s`, with the reason "%s"', opts.name, reason)
      end

      if opts.on_reject then
        local ok, err = opts.on_reject()
        if not ok then
          log:error("Failed to restore original content: %s", err)
          msg = fmt("%s\n\nWARNING: Failed to restore: %s. File may be inconsistent.", msg, err)
        end
      end

      return opts.output_handler(mk_response("error", msg))
    end)
  end, wait_opts)
end

---Parse Python-like JSON syntax from LLMs
---@param edits string
---@return string
local function parse_python_json(edits)
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
---@param args table
---@return table|nil, string|nil
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
  local python_converted = parse_python_json(args.edits)
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

---Read file content from disk
---@param path string
---@return string|nil, string|nil, table|nil The content, error, and file info
local function read_file(path)
  local p = Path:new(path)
  if not p:exists() or not p:is_file() then
    return nil, fmt("File does not exist or is not a file: `%s`", path)
  end

  local content = p:read()
  if not content then
    return nil, fmt("Could not read file content: `%s`", path)
  end

  local stat = vim.uv.fs_stat(path)
  local info = {
    has_trailing_newline = content:match("\n$") ~= nil,
    is_empty = content == "",
    mtime = stat and stat.mtime.sec or nil,
  }

  return content, nil, info
end

---Separate edits into substring and block types
---@param edits table[]
---@return table[], table[]
local function partition_edits_by_type(edits)
  local substring_edits = {}
  local block_edits = {}

  for i, edit in ipairs(edits) do
    local wrapper = { edit = edit, original_index = i }
    if edit.replaceAll and edit.oldText and not edit.oldText:find("\n") then
      table.insert(substring_edits, wrapper)
    else
      table.insert(block_edits, wrapper)
    end
  end

  return substring_edits, block_edits
end

---Extract explanation from action (top level or fallback to first edit)
---@param action table
---@return string
local function extract_explanation(action)
  local explanation = action.explanation or (action.edits and action.edits[1] and action.edits[1].explanation)
  return (explanation and explanation ~= "") and ("\n" .. explanation) or ""
end

---Execute substring replacements in parallel to avoid overlaps
---@param content string
---@param edits table[] Array of unwrapped edit objects
---@return string|nil content, string|nil error
local function process_substring_edits(content, edits)
  local replacements = {}

  for i, edit in ipairs(edits) do
    local matches = strategies.substring_exact_match(content, edit.oldText)

    if #matches == 0 then
      return nil, fmt("Substring edit %d: pattern '%s' not found in file", i, edit.oldText)
    end

    for _, match in ipairs(matches) do
      table.insert(replacements, {
        start_pos = match.start_pos,
        end_pos = match.end_pos,
        old_text = edit.oldText,
        new_text = edit.newText,
        edit_index = i,
      })
    end
  end

  table.sort(replacements, function(a, b)
    return a.start_pos > b.start_pos
  end)

  for _, replacement in ipairs(replacements) do
    local before = content:sub(1, replacement.start_pos - 1)
    local after = content:sub(replacement.end_pos + 1)
    content = before .. replacement.new_text .. after
  end

  return content, nil
end

---Extract edit objects from their wrapper structures
---@param edits table[] Array of {edit: table, original_index: number} wrappers
---@return table[] Array of unwrapped edit objects
local function extract_edits(edits)
  return vim.tbl_map(function(item)
    return item.edit
  end, edits)
end

---Validate and process substring edits in parallel
---@param content string
---@param edits table[] Array of {edit: table, original_index: number} wrappers
---@return string|nil content, table|nil error
local function validate_and_process_substring_edits(content, edits)
  local edited_content, error = process_substring_edits(content, extract_edits(edits))

  if error then
    return nil,
      {
        error = "substring_parallel_processing_failed",
        message = error,
        success = false,
      }
  end

  return edited_content, nil
end

---Build metadata for successfully processed substring edits
---@param edits table[] Array of {edit: table, original_index: number} wrappers
---@return table[] results, table[] selected_strategy
local function build_substring_metadata(edits)
  local results = {}
  local selected_strategy = {}
  local metadata = {
    strategy = "substring_exact_match_parallel",
    confidence = 1.0,
    selection_reason = "parallel_processing",
    auto_selected = true,
  }

  for _, item in ipairs(edits) do
    table.insert(results, vim.tbl_extend("force", metadata, { edit_index = item.original_index }))
    table.insert(selected_strategy, metadata.strategy)
  end

  return results, selected_strategy
end

---Handle special cases (empty file, overwrite mode)
---@param content string
---@param edits table[]
---@param opts table
---@return table|nil
local function handle_special_cases(content, edits, opts)
  if content == "" and #edits == 1 and (edits[1].oldText == "" or edits[1].oldText == nil) then
    return {
      success = true,
      content = edits[1].newText,
      edit_results = {
        {
          edit_index = 1,
          strategy = "empty_file_append",
          confidence = 1.0,
          selection_reason = "empty_file",
          auto_selected = true,
        },
      },
      strategies = { "empty_file_append" },
    }
  end

  if opts.mode == "overwrite" and #edits >= 1 then
    return {
      success = true,
      content = edits[1].newText,
      edit_results = {
        {
          edit_index = 1,
          strategy = "overwrite_mode",
          confidence = 1.0,
          selection_reason = "overwrite_mode",
          auto_selected = true,
        },
      },
      strategies = { "overwrite_mode" },
    }
  end

  return nil
end

---Check for conflicting edits
---@param content string
---@param edits table[]
---@param opts table
---@return table|nil
local function check_for_conflicts(content, edits, opts)
  if not opts.dry_run then
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
---@param edit table
---@param index number
---@param content string
---@param opts table
---@param partial_results table[]
---@return table|nil
local function validate_edit_fields(edit, index, content, opts, partial_results)
  if not edit.oldText and not (content == "" or opts.mode == "overwrite") then
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
---@param edit table
---@param index number
---@param content string
---@param partial_results table[]
---@param opts table
---@return string|nil new_content, table|nil error, table|nil result_info
local function process_single_edit(edit, index, content, partial_results, opts)
  local validation_error = validate_edit_fields(edit, index, content, opts, partial_results)
  if validation_error then
    return nil, validation_error, nil
  end

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

---Process edits sequentially
---@param content string
---@param edits table[]
---@param opts table|nil
---@return table
local function process_edits(content, edits, opts)
  opts = opts or {}

  local results = {}
  local block_edits = {}
  local selected_strategies = {}

  edits, block_edits = partition_edits_by_type(edits)

  if #edits > 0 then
    local edited_content, error = validate_and_process_substring_edits(content, edits)
    if error then
      return error
    end

    content = edited_content --[[@as string]]
    local substring_results, substring_strategies = build_substring_metadata(edits)
    vim.list_extend(results, substring_results)
    vim.list_extend(selected_strategies, substring_strategies)
  end

  local block_list = extract_edits(block_edits)

  local special_cases = handle_special_cases(content, block_list, opts)
  if special_cases then
    return special_cases
  end

  local conflicts = check_for_conflicts(content, block_list, opts)
  if conflicts then
    return conflicts
  end

  for _, edit_wrapper in ipairs(block_edits) do
    local edit = edit_wrapper.edit
    local original_index = edit_wrapper.original_index
    local edited_content, error, result_info = process_single_edit(edit, original_index, content, results, opts)

    if error then
      return error
    end

    content = edited_content--[[@as string]]
    table.insert(results, result_info)

    ---@diagnostic disable-next-line: need-check-nil
    table.insert(selected_strategies, result_info.strategy)
  end

  return {
    success = true,
    content = content,
    edit_results = results,
    strategies = selected_strategies,
  }
end

---@param action table
---@param chat_bufnr number
---@param output_handler function
---@param opts table|nil
local function edit_file(action, chat_bufnr, output_handler, opts)
  opts = opts or {}
  local path = helpers.validate_and_normalize_path(action.filepath)

  if not path then
    return output_handler(mk_response("error", fmt("Error: Invalid or non-existent filepath `%s`", action.filepath)))
  end

  local current_content, read_err, file_info = read_file(path)
  if not current_content then
    return output_handler(mk_response("error", read_err or "Unknown error reading file"))
  end

  if type(action.edits) == "string" then
    local ok, parsed = pcall(vim.json.decode, action.edits)
    if ok and type(parsed) == "table" then
      action.edits = parsed
    end
  end

  if #current_content > Constants.LIMITS.FILE_SIZE_MAX then
    return output_handler(
      mk_response(
        "error",
        fmt(
          "Error: File too large (%d bytes). Maximum supported size is %d bytes.",
          #current_content,
          Constants.LIMITS.FILE_SIZE_MAX
        )
      )
    )
  end

  local dry_run = process_edits(current_content, action.edits, {
    dry_run = true,
    path = path,
    file_info = file_info,
    mode = action.mode,
  })

  if not dry_run.success then
    local error_message = match_selector.format_helpful_error(dry_run, action.edits)
    return output_handler(mk_response("error", error_message))
  end

  local strategies_summary = table.concat(
    vim.tbl_map(function(strategy)
      return strategy:gsub("_", " ")
    end, dry_run.strategies),
    ", "
  )

  if action.dryRun then
    local ok, edit_word = pcall(utils.pluralize, #action.edits, "edit")
    if not ok then
      edit_word = "edit(s)"
    end
    return output_handler(
      mk_response(
        "success",
        fmt(
          "DRY RUN - Successfully processed %d %s using strategies: %s\nFile: `%s`\n\nTo apply these changes, set 'dryRun': false",
          #action.edits,
          edit_word,
          strategies_summary,
          action.filepath
        )
      )
    )
  end

  local write_ok, write_err = write_file(path, dry_run.content, file_info)
  if not write_ok then
    return output_handler(mk_response("error", fmt("Error writing to `%s`: %s", action.filepath, write_err)))
  end

  -- If the tool has been approved then skip showing the diff
  if Approvals:is_approved(chat_bufnr, { tool_name = "insert_edit_into_file" }) then
    return output_handler(
      mk_response("success", fmt("Edited `%s` file%s", action.filepath, extract_explanation(action)))
    )
  end

  local diff_id = math.random(10000000)
  local from_lines = vim.split(current_content, "\n", { plain = true })
  local to_lines = vim.split(dry_run.content, "\n", { plain = true })

  -- Detect filetype from path
  local ft = vim.filetype.match({ filename = path }) or "text"

  local diff_helpers = require("codecompanion.helpers")
  local diff_ui = diff_helpers.show_diff({
    from_lines = from_lines,
    to_lines = to_lines,
    ft = ft,
    title = action.filepath,
    diff_id = diff_id,
    chat_bufnr = chat_bufnr,
    tool_name = "insert_edit_into_file",
  })

  local success_msg = fmt("Edited `%s` file%s", action.filepath, extract_explanation(action))

  if opts.require_confirmation_after then
    return handle_approval({
      diff_id = diff_id,
      chat_bufnr = chat_bufnr,
      name = action.filepath,
      diff_ui = diff_ui,
      success_msg = success_msg,
      on_reject = function()
        return write_file(path, current_content, file_info)
      end,
      output_handler = output_handler,
    })
  else
    return output_handler(mk_response("success", success_msg))
  end
end

---@param bufnr number
---@param chat_bufnr number
---@param action table
---@param output_handler function
---@param opts table|nil
local function edit_buffer(bufnr, chat_bufnr, action, output_handler, opts)
  opts = opts or {}
  local diff_id = math.random(10000000)

  if not api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
  end

  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local current_content = table.concat(lines, "\n")
  local original_content = vim.deepcopy(lines)

  local file_info = {
    has_trailing_newline = current_content:match("\n$") ~= nil,
    is_empty = current_content == "",
  }

  if type(action.edits) == "string" then
    local ok, parsed = pcall(vim.json.decode, action.edits)
    if ok and type(parsed) == "table" then
      action.edits = parsed
    end
  end

  local dry_run = process_edits(current_content, action.edits, {
    dry_run = true,
    buffer = bufnr,
    file_info = file_info,
    mode = action.mode,
  })

  local buffer_name = api.nvim_buf_get_name(bufnr)
  local display_name = buffer_name ~= "" and vim.fn.fnamemodify(buffer_name, ":.") or fmt("buffer %d", bufnr)

  if not dry_run.success then
    local error_message = match_selector.format_helpful_error(dry_run, action.edits)
    return output_handler(
      mk_response("error", fmt("Error processing edits for `%s`:\n%s", display_name, error_message))
    )
  end

  local strategies_summary = table.concat(
    vim.tbl_map(function(strategy)
      return strategy:gsub("_", " ")
    end, dry_run.strategies),
    ", "
  )

  if action.dryRun then
    local ok, edit_word = pcall(utils.pluralize, #action.edits, "edit")
    if not ok then
      edit_word = "edit(s)"
    end
    return output_handler(
      mk_response(
        "success",
        fmt(
          "DRY RUN - Successfully processed %d %s using strategies: %s\nBuffer: `%s`\n\nTo apply these changes, set 'dryRun': false",
          #action.edits,
          edit_word,
          strategies_summary,
          display_name
        )
      )
    )
  end

  local final_lines = vim.split(dry_run.content, "\n", { plain = true })
  api.nvim_buf_set_lines(bufnr, 0, -1, false, final_lines)

  local success_msg = fmt("Edited `%s` buffer%s", display_name, extract_explanation(action))

  -- If the tool has been approved then skip showing the diff
  if Approvals:is_approved(chat_bufnr, { tool_name = "insert_edit_into_file" }) then
    api.nvim_buf_call(bufnr, function()
      vim.cmd("silent write")
    end)
    return output_handler(mk_response("success", success_msg))
  end

  local ft = vim.bo[bufnr].filetype or "text"

  local diff_helpers = require("codecompanion.helpers")
  local diff_ui = diff_helpers.show_diff({
    chat_bufnr = chat_bufnr,
    from_lines = original_content,
    to_lines = final_lines,
    ft = ft,
    title = display_name,
    diff_id = diff_id,
    tool_name = "insert_edit_into_file",
  })

  if opts.require_confirmation_after then
    return handle_approval({
      diff_id = diff_id,
      chat_bufnr = chat_bufnr,
      name = display_name,
      bufnr = bufnr,
      diff_ui = diff_ui,
      success_msg = success_msg,
      output_handler = output_handler,
    })
  end

  return output_handler(mk_response("success", success_msg))
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
      if args.edits then
        local fixed_args, error_msg = fix_edits_if_needed(args)
        if not fixed_args then
          return output_handler(mk_response("error", fmt("Invalid edits format: %s", error_msg)))
        end
        args = fixed_args
      end

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
