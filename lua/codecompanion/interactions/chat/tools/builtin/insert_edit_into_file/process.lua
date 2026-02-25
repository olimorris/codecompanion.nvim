--[[Edit processing pipeline for insert_edit_into_file]]

local match_selector = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.match_selector")
local strategies = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.strategies")

local fmt = string.format

local M = {}

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

---Extract edit objects from their wrapper structures
---@param edits table[] Array of {edit: table, original_index: number} wrappers
---@return table[] Array of unwrapped edit objects
local function extract_edits(edits)
  return vim.tbl_map(function(item)
    return item.edit
  end, edits)
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
---@return table|nil
local function check_for_conflicts(content, edits)
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
function M.process_edits(content, edits, opts)
  opts = opts or {}

  local results = {}
  local substring_edits, block_edits = partition_edits_by_type(edits)
  local selected_strategies = {}

  if #substring_edits > 0 then
    local edited_content, error = validate_and_process_substring_edits(content, substring_edits)
    if error then
      return error
    end

    content = edited_content --[[@as string]]
    local substring_results, substring_strategies = build_substring_metadata(substring_edits)
    vim.list_extend(results, substring_results)
    vim.list_extend(selected_strategies, substring_strategies)
  end

  local block_list = extract_edits(block_edits)

  local special_cases = handle_special_cases(content, block_list, opts)
  if special_cases then
    return special_cases
  end

  local conflicts = check_for_conflicts(content, block_list)
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

return M
