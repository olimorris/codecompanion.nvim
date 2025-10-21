local Path = require("plenary.path")

local codecompanion = require("codecompanion")
local config = require("codecompanion.config")
local diff = require("codecompanion.strategies.chat.helpers.diff")
local edit_tool_exp_strategies = require("codecompanion.strategies.chat.tools.catalog.edit_file.strategies")
local helpers = require("codecompanion.strategies.chat.helpers")
local match_selector = require("codecompanion.strategies.chat.tools.catalog.edit_file.match_selector")
local wait = require("codecompanion.strategies.chat.helpers.wait")

local buffers = require("codecompanion.utils.buffers")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")

local api = vim.api
local fmt = string.format

-- Enhanced Python-like parser for handling LLM's mixed Python/JSON syntax
---@param edits_string string The string containing edits in Python-like format
---@return string The converted JSON-like string
local function parse_python_like_edits(edits_string)
  log:trace("[Edit Tool Exp] Trying enhanced Python-like parser")

  -- Step 1: Fix boolean values first (before quote conversion)
  local fixed = edits_string
  fixed = fixed:gsub(":%s*True([,%]}%s])", ": true%1")
  fixed = fixed:gsub(":%s*False([,%]}%s])", ": false%1")
  fixed = fixed:gsub("^%s*True([,%]}%s])", "true%1")
  fixed = fixed:gsub("^%s*False([,%]}%s])", "false%1")
  -- Also handle end of string
  fixed = fixed:gsub(":%s*True$", ": true")
  fixed = fixed:gsub(":%s*False$", ": false")

  -- Step 1.5: Normalize escape sequences (fix double-escaping issues)
  fixed = fixed:gsub("\\\\n", "\n") -- \\n -> \n (newlines)
  fixed = fixed:gsub("\\\\t", "\t") -- \\t -> \t (tabs)
  fixed = fixed:gsub("\\\\r", "\r") -- \\r -> \r (carriage returns)
  fixed = fixed:gsub("\\\\\\\\", "\\") -- \\\\ -> \ (backslashes)

  -- Step 2: Convert single quotes to double quotes carefully
  -- Handle existing double quotes and escaped single quotes inside strings
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

  log:trace("[Edit Tool Exp] Edits field is a string, attempting to parse as JSON")

  -- First, try standard JSON parsing
  local success, parsed_edits = pcall(vim.json.decode, args.edits)

  if success and type(parsed_edits) == "table" then
    args.edits = parsed_edits
    return args, nil
  end

  -- If that failed, try minimal fixes for common LLM JSON issues
  log:trace("[Edit Tool Exp] Standard JSON parsing failed, trying fixes")

  local fixed_json = args.edits

  -- Fix keys first
  fixed_json = fixed_json:gsub("{'oldText':", '{"oldText":')
  fixed_json = fixed_json:gsub("'newText':", '"newText":')
  fixed_json = fixed_json:gsub("'replaceAll':", '"replaceAll":')

  -- Fix values - simple approach
  -- Pattern: : 'value' -> : "value" (after colons)
  fixed_json = fixed_json:gsub(": '([^']*)'", ': "%1"')

  -- Pattern: , 'value' -> , "value" (after commas)
  fixed_json = fixed_json:gsub(", '([^']*)'", ', "%1"')

  -- Fix boolean values (Python-style to JSON-style)
  fixed_json = fixed_json:gsub(": False([,}%]])", ": false%1")
  fixed_json = fixed_json:gsub(": True([,}%]])", ": true%1")

  -- Try parsing the fixed JSON
  success, parsed_edits = pcall(vim.json.decode, fixed_json)

  if success and type(parsed_edits) == "table" then
    args.edits = parsed_edits
    log:trace("[Edit Tool Exp] Successfully fixed and parsed edits JSON")
    return args, nil
  end

  -- FALLBACK: Try enhanced Python-like parser
  local python_converted = parse_python_like_edits(args.edits)
  if python_converted then
    success, parsed_edits = pcall(vim.json.decode, python_converted)
    if success and type(parsed_edits) == "table" then
      args.edits = parsed_edits
      log:trace("[Edit Tool Exp] Successfully parsed Python-like syntax")
      return args, nil
    end
  end

  -- If all else fails, provide helpful error
  return nil, fmt("Could not parse edits as JSON. Original: %s", args.edits:sub(1, 200))
end

local SYSTEM_PROMPT = [[Use edit_tool_exp for safe, reliable file editing with advanced capabilities.

# Quick Reference – Basic Usage
```json
{
  "filepath": "path/to/file.js",
  "edits": [
    {
      "oldText": "function getName() {\n return this.name;\n}",
      "newText": "function getFullName() {\n return this.firstName + ' ' + this.lastName;\n}",
      "replaceAll": false
    }
  ],
  "dryRun": false,
  "mode": "append",
  "explanation": "Additional notes"
}
```

# CRITICAL SCHEMA REQUIREMENTS
**EVERY edit MUST have BOTH oldText AND newText - NO EXCEPTIONS**

Common mistakes that will cause FAILURE:
❌ Missing oldText field (required!)
❌ Missing newText field (required!)
❌ Putting "filepath" inside edits array (it goes at top level)
❌ Putting "explanation" inside edits array (it goes at top level)
❌ Making "edits" a string instead of an array
❌ Using single quotes instead of double quotes

Correct structure:
✓ filepath: at TOP LEVEL
✓ edits: ARRAY of objects at TOP LEVEL
✓ Each edit object: {"oldText": "...", "newText": "...", "replaceAll": false}
✓ explanation: at TOP LEVEL (optional)

# Parameters, Rules, and Best Practices
- **filepath**: Required. Top-level field. File to edit.
- **edits**: Required. Top-level ARRAY (not string). Each edit needs "oldText" AND "newText".
- **oldText**: REQUIRED in every edit. Exact text to find. Cannot be empty for normal edits.
- **newText**: REQUIRED in every edit. Replacement text. Can be empty for deletions.
- **replaceAll**: Optional. Set to true for global replacements (substring mode if no newlines).
- **dryRun**: Optional. Preview changes if true. Default false.
- **mode**: Optional. "append" (default) or "overwrite" (replace entire file).
- **explanation**: Optional. Top-level field. Description of changes.


## Edit Operations:

### Standard Replacement (Block/Line Matching):
{
  "oldText": "exact text to find",
  "newText": "replacement text",
  "replaceAll": false  // true to replace ALL occurrences
}

### Substring Replacement (Token/Pattern Matching):
When `replaceAll: true` and `oldText` contains NO newlines, the tool automatically uses substring matching for efficient token/keyword replacement:

{
  "oldText": "var ",
  "newText": "let ",
  "replaceAll": true
}

**Behavior:**
- Finds ALL plain-text occurrences of oldText within the file (no regex)
- Does NOT require full-line match - replaces within lines
- Perfect for: keyword changes (var→let), API renames (oldAPI.→newAPI.), token updates
- Limit: 1000 matches maximum for performance
- Must NOT contain newlines in oldText

**Examples:**
```
// Replace all var declarations with let
{ "oldText": "var ", "newText": "let ", "replaceAll": true }

// Update API namespace
{ "oldText": "oldNS.", "newText": "newNS.", "replaceAll": true }

// Remove trailing spaces
{ "oldText": "TODO: ", "newText": "DONE: ", "replaceAll": true }
```

**CRITICAL WARNING - Overlapping Patterns:**
When using multiple substring replacements, patterns can overlap and cause double replacements!

**Bad Example (WILL CAUSE BUGS):**
```
// DON'T DO THIS - 'util' will match inside 'cc_diff_utils'!
{ "oldText": "diff_utils", "newText": "cc_diff_utils", "replaceAll": true }
{ "oldText": "util", "newText": "cc_util", "replaceAll": true }
// Result: cc_diff_utils → cc_diff_cc_utils (WRONG!)
```

**Good Example (Use specific patterns):**
```
// DO THIS - Use word boundaries or delimiters
{ "oldText": "local diff_utils", "newText": "local cc_diff_utils", "replaceAll": true }
{ "oldText": "local util ", "newText": "local cc_util ", "replaceAll": true }
// Or combine into one edit with full context
```

**Rule:** If newText from Edit #1 contains oldText from Edit #2, you have overlapping patterns!
- Check: Does "cc_diff_utils" contain "util"? YES → Will cause double replacement
- Solution: Use more specific patterns that won't match the replaced text
- Alternative: Make separate edit_tool_exp calls for each rename instead of batching

**NOT for substring mode:**
- Multi-line text (use block matching instead)
- Structural changes (functions, classes)
- When you need indentation/whitespace context
- Overlapping patterns (causes double replacements)

### File Boundary Operations:
- **Start of file**: Use oldText: "^" or "<<START>>"
- **End of file**: Use oldText: "$" or "<<END>>"
- **Replacement pattern**: oldText: "first line", newText: "new content\nfirst line"

### Empty Files:
{
  "oldText": "",  // Empty oldText for empty files
  "newText": "initial content"
}

### Deletion:
{
  "oldText": "text to remove",
  "newText": ""  // Empty newText deletes content
}

### Complete File Replacement:
{
  "mode": "overwrite",
  "edits": [{ "oldText": "", "newText": "entire new file content" }]
}

## Smart Matching Features:
- **Exact matching**: Tries exact text first
- **Substring matching**: For replaceAll with single-line patterns (automatic)
- **Whitespace tolerance**: Handles spacing/indentation differences
- **Newline variants**: Works with/without trailing newlines (fixes echo "text" > file issues)
- **Block anchoring**: Uses first/last lines for context
- **Adaptive ambiguity resolution**: If matches are too similar, tries next strategy automatically
- **Conflict detection**: Prevents overlapping edits

**CRITICAL JSON REQUIREMENTS - TOOL WILL FAIL IF NOT FOLLOWED**:
- Use double quotes (") ONLY - never single quotes (')
- "edits" MUST be a JSON array [ ] - NEVER a string
- Boolean values: true/false (not "True"/"False" or "true"/"false")
- NO string wrapping of JSON objects or arrays
- NO double-escaping of quotes or backslashes

### Correct Format:
{
  "filepath": "path/to/file.js",
  "edits": [
    {
      "oldText": "function getName() {\n  return this.name;\n}",
      "newText": "function getFullName() {\n  return this.firstName + ' ' + this.lastName;\n}"
    }
  ],
  "dryRun": false
}

### Incorrect Format (will cause errors):
{
  "filepath": "path/to/file.js",
  "edits": "[{'oldText': 'function getName()', 'newText': 'function getFullName()'}]",  // Wrong: edits as string
  "dryRun": "false"  // Wrong: boolean as string
}

## oldText Format Rules:
**Critical**: oldText must match file content exactly
- **Never include line numbers** (like "117:", "118:") in oldText
- **Use actual text content only**, exactly as it appears in the file
- **Match exact quotes and escaping** - use "" not \"\"
- **Copy text directly** from file content, don't add line prefixes
- **No editor artifacts** - exclude gutters, line numbers, syntax highlighting markers

### Wrong Examples:
 "oldText": "117:  local cwd_icon = \"\""  // Line numbers included
 "oldText": "→   function test()"        // Tab/space indicators included
 "oldText": "│ return value"            // Editor gutter characters included
 "oldText": "local name = \\\"John\\\""  // Double-escaped quotes

### Correct Examples:
 "oldText": "local cwd_icon = \"\""      // Clean, actual file content
 "oldText": "function test()"           // No editor artifacts
 "oldText": "return value"              // Pure code content
 "oldText": "local name = \"John\""     // Proper escaping

## Best Practices:
 **Be specific**: Include enough context (function names, unique variables)
 **Use exact formatting**: Match spaces, tabs, indentation exactly
 **Start with dryRun: false**: for testing the tool, always set dryRun to false unless the user explicitly requests a dry run
 **Sequential edits**: Each edit assumes previous ones completed
 **Handle edge cases**: Empty files, boundary insertions, deletions

## Error Recovery:
- System provides helpful error messages with suggestions
- Handles malformed input gracefully
- Detects ambiguous matches and requests clarification
- Suggests adding more context for unique identification

## Examples:

### Multiple Sequential Edits:
{
  "filepath": "config.js",
  "edits": [
    { "oldText": "const PORT = 3000", "newText": "const PORT = 8080" },
    { "oldText": "DEBUG = false", "newText": "DEBUG = true" }
  ]
}

### Substring Replacement Across File:
{
  "filepath": "src/app.js",
  "edits": [
    { "oldText": "var ", "newText": "let ", "replaceAll": true }
  ]
}

### Add to File Start:
{
  "filepath": "script.py",
  "edits": [{ "oldText": "^", "newText": "#!/usr/bin/env python3\n" }]
}

### Block Replace All (Multi-line):
{
  "filepath": "legacy.js",
  "edits": [{
    "oldText": "function oldHandler() {\n  return false;\n}",
    "newText": "function oldHandler() {\n  return true;\n}",
    "replaceAll": true
  }]
}

## Common Issues & Solutions:

 **"No confident matches found"**
- Check formatting: spaces, tabs, newlines must match exactly
- Add more context: include function names, surrounding lines
- For files without trailing newlines (like echo "text" > file): try both variants

 **"Line numbers in oldText"**
- **Problem**: Including line numbers like "117:  local function test()"
- **Solution**: Use only the actual code content: "local function test()"
- **Remember**: oldText should match file content exactly, not what you see in editors with line numbers

 **"Ambiguous matches found"**
- **NEW BEHAVIOR**: When matches are too similar, the tool tries the next matching strategy automatically for better disambiguation
- **For substring replacement**: Use replaceAll: true to replace ALL occurrences at once
- **For targeted edits**: Include more surrounding context in oldText to make it unique

**Example - Multiple identical function definitions:**
```
// Strategy 1 finds multiple similar matches → tries strategy 2 automatically
// Strategy 2 (block anchor) might find unique match using context

// To edit ALL occurrences at once:
{ "oldText": "function process() {", "newText": "function process() {\n  // updated", "replaceAll": true }

// To edit a specific occurrence, add unique context:
{ "oldText": "class DataHandler {\n  function process() {", "newText": "class DataHandler {\n  function process() {\n    // updated specific one" }
```

**Example - Fixing Line Number Issues:**
```
 Wrong (includes line numbers):
{
  "oldText": "117:  -- Function to get the current working directory name\n118:  ---@return string\n119:  local function get_cwd()"
}

 Correct (actual file content only):
{
  "oldText": "-- Function to get the current working directory name\n---@return string\nlocal function get_cwd()"
}
```

 **"Conflicting edits"**
- Multiple edits target overlapping text
- Combine overlapping edits into a single operation
- Ensure edits are sequential and non-overlapping

 **Working with different file types:**
- Empty files: Use oldText: "" for first content
- Files from echo/printf: System handles missing newlines automatically
- Large files: Performance optimized with size limits
- Unicode content: Full UTF-8 support

 **When to use each approach:**
- Use position markers (^/$) when you don't know file content
- Use replacement patterns when you know the first/last lines
- Use overwrite mode for complete file replacement
- Use replaceAll for global find/replace operations

The system is extremely robust and handles whitespace differences, newline variations, and provides intelligent error messages when matches are ambiguous.]]

-- Read file content safely
---@param filepath string
---@return string|nil, string|nil, table|nil The content, error, and file info
local function read_file_content(filepath)
  local p = Path:new(filepath)
  if not p:exists() or not p:is_file() then
    return nil, fmt("File does not exist or is not a file: %s", filepath)
  end

  local content = p:read()
  if not content then
    return nil, fmt("Could not read file content: %s", filepath)
  end

  -- Track file metadata for proper handling
  local file_info = {
    has_trailing_newline = content:match("\n$") ~= nil,
    is_empty = content == "",
  }

  return content, nil, file_info
end

-- Write file content
---@param filepath string
---@param content string
---@param file_info table|nil
---@return boolean, string|nil Success status and error message
local function write_file_content(filepath, content, file_info)
  file_info = file_info or {}

  -- Preserve original newline behavior
  if file_info.has_trailing_newline == false and content:match("\n$") then
    content = content:gsub("\n$", "")
  elseif file_info.has_trailing_newline == true and not content:match("\n$") then
    content = content .. "\n"
  end

  local p = Path:new(filepath)
  local ok, err = pcall(function()
    p:write(content, "w")
  end)

  if not ok then
    return false, fmt("Failed to write file: %s", err)
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
    local matches = edit_tool_exp_strategies.substring_exact_match(content, edit.oldText)

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
    local substring_edit_list = vim.tbl_map(function(item)
      return item.edit
    end, substring_edits)

    local parallel_result, parallel_error = process_substring_edits_parallel(current_content, substring_edit_list)

    if not parallel_result then
      return {
        success = false,
        error = "substring_parallel_processing_failed",
        message = parallel_error,
      }
    end

    current_content = parallel_result

    -- Record results for all substring edits
    for _, item in ipairs(substring_edits) do
      table.insert(results, {
        edit_index = item.original_index,
        strategy = "substring_exact_match_parallel",
        confidence = 1.0,
        selection_reason = "parallel_processing",
        auto_selected = true,
      })
      table.insert(strategies_used, "substring_exact_match_parallel")
    end

    log:debug("[Edit Tool Exp] Applied %d substring edits in parallel", #substring_edits)
  end

  -- Step 3: Process block/single edits sequentially
  edits = vim.tbl_map(function(item)
    return item.edit
  end, other_edits)

  -- Handle empty file case
  if current_content == "" and #edits == 1 and (edits[1].oldText == "" or edits[1].oldText == nil) then
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

  -- Check for conflicts first
  if not options.dry_run then
    local conflicts = match_selector.detect_edit_conflicts(current_content, edits)
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

  for i, edit in ipairs(edits) do
    -- Validate required fields
    if not edit.oldText and not (current_content == "" or options.mode == "overwrite") then
      return {
        success = false,
        failed_at_edit = i,
        error = "missing_oldText",
        partial_results = results,
        message = "Edit #"
          .. i
          .. " is missing required field 'oldText'. Every edit MUST have both 'oldText' and 'newText' fields.",
      }
    end

    if not edit.newText and edit.newText ~= "" then
      return {
        success = false,
        failed_at_edit = i,
        error = "missing_newText",
        partial_results = results,
        message = "Edit #"
          .. i
          .. " is missing required field 'newText'. Every edit MUST have both 'oldText' and 'newText' fields.",
      }
    end

    -- Find matches using edit tool exp strategies
    local match_result = edit_tool_exp_strategies.find_best_match(current_content, edit.oldText, edit.replaceAll)

    if not match_result.success then
      return {
        success = false,
        failed_at_edit = i,
        error = match_result.error,
        partial_results = results,
        attempted_strategies = match_result.attempted_strategies,
      }
    end

    -- Select best match from candidates
    local selection_result = edit_tool_exp_strategies.select_best_match(match_result.matches, edit.replaceAll)

    if not selection_result.success then
      return {
        success = false,
        failed_at_edit = i,
        error = selection_result.error,
        matches = selection_result.matches,
        suggestion = selection_result.suggestion,
        partial_results = results,
      }
    end

    -- Apply the replacement if not dry run
    if not options.dry_run then
      current_content =
        edit_tool_exp_strategies.apply_replacement(current_content, selection_result.selected, edit.newText)
    else
      -- For dry run, simulate the change for diff generation
      local temp_content =
        edit_tool_exp_strategies.apply_replacement(current_content, selection_result.selected, edit.newText)
      current_content = temp_content
    end

    table.insert(results, {
      edit_index = i,
      strategy = match_result.strategy_used,
      confidence = selection_result.selected.confidence
        or (type(selection_result.selected) == "table" and selection_result.selected[1] and selection_result.selected[1].confidence)
        or 0,
      selection_reason = selection_result.selection_reason,
      auto_selected = selection_result.auto_selected,
    })

    table.insert(strategies_used, match_result.strategy_used)
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
  local filepath = helpers.validate_and_normalize_path(action.filepath)

  if not filepath then
    return output_handler({
      status = "error",
      data = fmt("Error: Invalid or non-existent filepath `%s`", action.filepath),
    })
  end

  -- Read current file content
  local current_content, read_err, file_info = read_file_content(filepath)
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
  if #current_content > 1000000 then -- 1MB limit
    return output_handler({
      status = "error",
      data = fmt("Error: File too large (%d bytes). Maximum supported size is 1MB.", #current_content),
    })
  end

  -- Process edits with dry run first
  local dry_run_result = process_edits_sequentially(current_content, action.edits, {
    dry_run = true,
    filepath = filepath,
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

  -- Generate summary (using existing diff system for interactive diffs)
  local strategies_summary = table.concat(
    vim.tbl_map(function(strategy)
      return strategy:gsub("_", " ")
    end, dry_run_result.strategies_used),
    ", "
  )

  local success_message = fmt(
    "Successfully processed %d edit(s) using strategies: %s\n\nChanges will be shown in diff view.",
    #action.edits,
    strategies_summary
  )

  -- Handle dry run mode
  if action.dryRun then
    return output_handler({
      status = "success",
      data = "DRY RUN - " .. success_message .. "\n\nTo apply these changes, set 'dryRun': false",
    })
  end

  -- Auto-apply in YOLO mode
  if vim.g.codecompanion_yolo_mode then
    log:debug("[Edit Tool Exp] Auto-applying changes (YOLO mode)")
    local write_ok, write_err = write_file_content(filepath, dry_run_result.final_content, file_info)
    if not write_ok then
      return output_handler({
        status = "error",
        data = write_err,
      })
    end

    return output_handler({
      status = "success",
      data = fmt("Applied %d edit(s) to %s", #action.edits, action.filepath),
    })
  end

  -- Create diff for user approval
  local diff_id = math.random(10000000)
  local original_lines = vim.split(current_content, "\n", { plain = true })
  local should_diff = diff.create(filepath, diff_id, {
    original_content = original_lines,
  })

  local final_success = {
    status = "success",
    data = success_message,
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
        -- Apply the actual changes
        local final_result = process_edits_sequentially(current_content, action.edits, {
          dry_run = false,
          file_info = file_info,
          mode = action.mode,
        })
        if final_result.success then
          local write_ok, write_err = write_file_content(filepath, final_result.final_content, file_info)
          if write_ok then
            response = final_success
          else
            response = { status = "error", data = write_err }
          end
        else
          response = { status = "error", data = "Failed to apply changes: " .. final_result.error }
        end
      else
        if result.timeout and should_diff and should_diff.reject then
          should_diff:reject()
        end
        response = {
          status = "error",
          data = result.timeout and "User failed to accept the edits in time" or "User rejected the edits",
        }
      end

      codecompanion.restore(chat_bufnr)
      return output_handler(response)
    end, wait_opts)
  else
    -- Apply changes immediately
    local final_result = process_edits_sequentially(current_content, action.edits, {
      dry_run = false,
      file_info = file_info,
      mode = action.mode,
    })
    if final_result.success then
      local write_ok, write_err = write_file_content(filepath, final_result.final_content, file_info)
      if write_ok then
        return output_handler(final_success)
      else
        return output_handler({ status = "error", data = write_err })
      end
    else
      return output_handler({ status = "error", data = "Failed to apply changes: " .. final_result.error })
    end
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

  if not dry_run_result.success then
    local error_message = match_selector.format_helpful_error(dry_run_result, action.edits)
    return output_handler({
      status = "error",
      data = error_message,
    })
  end

  -- Apply changes to buffer
  local final_lines = vim.split(dry_run_result.final_content, "\n", { plain = true })
  api.nvim_buf_set_lines(bufnr, 0, -1, false, final_lines)

  -- Create diff
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

  -- Auto-save in YOLO mode
  if vim.g.codecompanion_yolo_mode then
    log:debug("[Edit Tool Exp] Auto-saving buffer (YOLO mode)")
    api.nvim_buf_call(bufnr, function()
      vim.cmd("silent write")
    end)
  end

  local strategies_summary = table.concat(
    vim.tbl_map(function(strategy)
      return strategy:gsub("_", " ")
    end, dry_run_result.strategies_used),
    ", "
  )

  local success = {
    status = "success",
    data = fmt(
      "Applied %d edit(s) to buffer using strategies: %s\n%s",
      #action.edits,
      strategies_summary,
      action.explanation or ""
    ),
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
          data = result.timeout and "User failed to accept the edits in time" or "User rejected the edits",
        }
      end

      codecompanion.restore(chat_bufnr)
      return output_handler(response)
    end, wait_opts)
  else
    return output_handler(success)
  end
end

---@class CodeCompanion.Tool.EditToolExp: CodeCompanion.Tools.Tool
return {
  name = "edit_tool_exp",
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
      name = "edit_tool_exp",
      description = "Robustly edit files with multiple automatic fallback strategies. Handles whitespace differences, indentation variations, and ambiguous matches intelligently.",
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
              required = { "oldText", "newText" },
            },
          },
          dryRun = {
            type = "boolean",
            default = true,
            description = "Preview changes without applying them. Recommended to start with true to see what will be changed.",
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
        required = { "filepath", "edits" },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  system_prompt = SYSTEM_PROMPT,
  handlers = {
    ---The handler to determine whether to prompt the user for approval
    ---@param self CodeCompanion.Tool.EditToolExp
    ---@param tools CodeCompanion.Tools
    ---@param config table The tool configuration
    ---@return boolean
    prompt_condition = function(self, tools, config)
      local opts = config["edit_tool_exp"] and config["edit_tool_exp"].opts or {}

      local args = self.args
      local bufnr = buffers.get_bufnr_from_path(args.filepath)
      if bufnr then
        if opts.requires_approval and opts.requires_approval.buffer then
          return true
        end
        return false
      end

      if opts.requires_approval and opts.requires_approval.file then
        return true
      end
      return false
    end,

    ---@param tools CodeCompanion.Tools The tool object
    ---@return nil
    on_exit = function(tools) end,
  },
  output = {
    ---@param self CodeCompanion.Tool.EditToolExp
    ---@param tools CodeCompanion.Tools
    ---@return nil|string
    prompt = function(self, tools)
      local args = self.args
      local filepath = vim.fn.fnamemodify(args.filepath, ":.")
      local edit_count = args.edits and #args.edits or 0
      return fmt("Apply %d edit(s) to %s?", edit_count, filepath)
    end,

    ---@param self CodeCompanion.Tool.EditToolExp
    ---@param tool CodeCompanion.Tools
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, tool, cmd, stdout)
      local chat = tool.chat
      local llm_output = vim.iter(stdout):flatten():join("\n")
      chat:add_tool_output(self, llm_output)
    end,

    ---@param self CodeCompanion.Tool.EditToolExp
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
