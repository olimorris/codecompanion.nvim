--[[
===============================================================================
    File:       codecompanion/interactions/chat/tools/builtin/insert_edit_into_file/init.lua
-------------------------------------------------------------------------------
    Description:
      Main orchestration for the insert_edit_into_file tool.

      This tool enables LLMs to make deterministic file edits through function
      calling. It supports various edit operations: standard replacements,
      replace-all, substring matching, file boundaries (start/end), and
      complete file overwrites.

      Key features:
      - Atomic operations: all edits succeed or none are applied
      - Smart matching with multiple fallback strategies
      - Substring mode for efficient token/keyword replacement
      - Handles whitespace differences and indentation variations
      - Size limits: 2MB file, 50KB search text

      This code is licensed under the Apache-2.0 License.
-------------------------------------------------------------------------------
    Attribution:
      If you use or distribute this code, please credit:
      CodeCompanion.nvim
===============================================================================
--]]

local Path = require("plenary.path")
local approvals = require("codecompanion.interactions.chat.tools.approvals")
local config = require("codecompanion.config")
local constants = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.constants")
local match_selector = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.match_selector")
local strategies = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.strategies")

local buf_utils = require("codecompanion.utils.buffers")
local file_utils = require("codecompanion.utils.files")
local ui_utils = require("codecompanion.utils.ui")

local api = vim.api
local fmt = string.format

local diff_enabled = config.display.diff.enabled == true

---Load prompt from markdown file
---@return string The prompt content
local function load_prompt()
  local source_path = debug.getinfo(1, "S").source:sub(2)
  local dir = vim.fn.fnamemodify(source_path, ":h")
  local prompt_path = Path:new(dir, "prompt.md")
  return prompt_path:read()
end

local PROMPT = load_prompt()

---Create response for output_cb
---@param status "success"|"error"
---@param msg string
---@return table
local function make_response(status, msg)
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

---Show diff and handle approval flow for edits
---@param opts table
---@return any
local function approve_and_diff(opts)
  if opts.approved or diff_enabled == false or opts.require_confirmation_after == false then
    return opts.apply_fn()
  end

  local diff_id = math.random(10000000)
  local diff_helpers = require("codecompanion.helpers")

  diff_helpers.show_diff({
    chat_bufnr = opts.chat_bufnr,
    diff_id = diff_id,
    ft = opts.ft,
    from_lines = opts.from_lines,
    to_lines = opts.to_lines,
    title = opts.title,
    tool_name = "insert_edit_into_file",
    keymaps = {
      on_always_accept = function()
        approvals:always(opts.chat_bufnr, { tool_name = "insert_edit_into_file" })
      end,
      on_accept = function()
        opts.apply_fn()
      end,
      on_reject = function()
        get_rejection_reason(function(reason)
          local msg = fmt('User rejected the edits for `%s`, with the reason "%s"', opts.title, reason)
          opts.output_cb(make_response("error", msg))
        end)
      end,
    },
  })
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
  local tool_utils = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.utils")
  local python_converted = tool_utils.parse_python_json(args.edits)
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

---@param action table
---@param opts table|nil
local function edit_file(action, opts)
  opts = opts or {}
  local path = file_utils.validate_and_normalize_path(action.filepath)

  if not path then
    return opts.output_cb(make_response("error", fmt("Error: Invalid or non-existent filepath `%s`", action.filepath)))
  end

  local original_content, read_err, file_info = read_file(path)
  if not original_content then
    return opts.output_cb(make_response("error", read_err or "Unknown error reading file"))
  end

  if type(action.edits) == "string" then
    local ok, parsed = pcall(vim.json.decode, action.edits)
    if ok and type(parsed) == "table" then
      action.edits = parsed
    end
  end

  if #original_content > constants.LIMITS.FILE_SIZE_MAX then
    return opts.output_cb(
      make_response(
        "error",
        fmt(
          "Error: File too large (%d bytes). Maximum supported size is %d bytes.",
          #original_content,
          constants.LIMITS.FILE_SIZE_MAX
        )
      )
    )
  end

  local edit = process_edits(original_content, action.edits, {
    path = path,
    file_info = file_info,
    mode = action.mode,
  })

  if not edit.success then
    local error_message = match_selector.format_helpful_error(edit, action.edits)
    return opts.output_cb(make_response("error", error_message))
  end

  local success_msg = fmt("Edited `%s` file%s", action.filepath, extract_explanation(action))

  return approve_and_diff({
    from_lines = vim.split(original_content, "\n", { plain = true }),
    to_lines = vim.split(edit.content, "\n", { plain = true }),
    apply_fn = function()
      local write_ok, write_err = write_file(path, edit.content, file_info)
      if not write_ok then
        return opts.output_cb(make_response("error", fmt("Error writing to `%s`: %s", action.filepath, write_err)))
      end
      opts.output_cb(make_response("success", success_msg))
    end,
    approved = approvals:is_approved(opts.chat_bufnr, { tool_name = "insert_edit_into_file" }),
    chat_bufnr = opts.chat_bufnr,
    ft = vim.filetype.match({ filename = path }) or "text",
    output_cb = opts.output_cb,
    require_confirmation_after = opts.tool_opts.require_confirmation_after,
    success_msg = success_msg,
    title = action.filepath,
  })
end

---@param bufnr number
---@param opts table|nil
local function edit_buffer(bufnr, opts)
  opts = opts or {}

  if not api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
  end

  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local original_content = table.concat(lines, "\n")

  local file_info = {
    has_trailing_newline = original_content:match("\n$") ~= nil,
    is_empty = original_content == "",
  }

  if type(opts.action.edits) == "string" then
    local ok, parsed = pcall(vim.json.decode, opts.action.edits)
    if ok and type(parsed) == "table" then
      opts.action.edits = parsed
    end
  end

  local edit = process_edits(original_content, opts.action.edits, {
    buffer = bufnr,
    file_info = file_info,
    mode = opts.action.mode,
  })

  local buffer_name = api.nvim_buf_get_name(bufnr)
  local display_name = buffer_name ~= "" and vim.fn.fnamemodify(buffer_name, ":.") or fmt("buffer %d", bufnr)

  if not edit.success then
    local error_message = match_selector.format_helpful_error(edit, opts.action.edits)
    return opts.output_cb(
      make_response("error", fmt("Error processing edits for `%s`:\n%s", display_name, error_message))
    )
  end

  local content = vim.split(edit.content, "\n", { plain = true })
  local success_msg = fmt("Edited `%s` buffer%s", display_name, extract_explanation(opts.action))

  return approve_and_diff({
    from_lines = vim.deepcopy(lines),
    to_lines = content,
    apply_fn = function()
      api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
      api.nvim_buf_call(bufnr, function()
        vim.cmd("silent write")
      end)
      opts.output_cb(make_response("success", success_msg))
    end,
    approved = approvals:is_approved(opts.chat_bufnr, { tool_name = "insert_edit_into_file" }),
    chat_bufnr = opts.chat_bufnr,
    ft = vim.bo[bufnr].filetype or "text",
    output_cb = opts.output_cb,
    require_confirmation_after = opts.tool_opts.require_confirmation_after,
    success_msg = success_msg,
    title = display_name,
  })
end

---@class CodeCompanion.Tool.InsertEditIntoFile: CodeCompanion.Tools.Tool
return {
  name = "insert_edit_into_file",
  cmds = {
    ---Execute the experimental edit tool commands
    ---@param self CodeCompanion.Tools
    ---@param args table The arguments from the LLM's tool call
    ---@param opts {}
    ---@return nil|table
    function(self, args, opts)
      if args.edits then
        local fixed_args, error_msg = fix_edits_if_needed(args)
        if not fixed_args then
          return opts.output_cb(make_response("error", fmt("Invalid edits format: %s", error_msg)))
        end
        args = fixed_args
      end

      local bufnr = buf_utils.get_bufnr_from_path(args.filepath)
      if bufnr then
        return edit_buffer(
          bufnr,
          { chat_bufnr = self.chat.bufnr, action = args, output_cb = opts.output_cb, tool_opts = self.tool.opts }
        )
      end
      return edit_file(args, { chat_bufnr = self.chat.bufnr, output_cb = opts.output_cb, tool_opts = self.tool.opts })
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
        required = { "filepath", "edits", "explanation", "mode" },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  handlers = {
    ---The handler to determine whether to prompt the user for approval
    ---@param self CodeCompanion.Tool.InsertEditIntoFile
    ---@param meta { tools: table }
    ---@return boolean
    prompt_condition = function(self, meta)
      local args = self.args
      local bufnr = buf_utils.get_bufnr_from_path(args.filepath)
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
  },
  output = {
    ---@param self CodeCompanion.Tool.InsertEditIntoFile
    ---@param stderr table The error output from the command
    ---@param meta { tools: CodeCompanion.Tools, cmd: string}
    ---@return nil
    error = function(self, stderr, meta)
      if stderr then
        local chat = meta.tools.chat
        local errors = vim.iter(stderr):flatten():join("\n")
        chat:add_tool_output(self, "**Error:**\n" .. errors)
      end
    end,

    ---@param self CodeCompanion.Tool.InsertEditIntoFile
    ---@param meta {tools: CodeCompanion.Tools}
    ---@return nil|string
    prompt = function(self, meta)
      local args = self.args
      local filepath = vim.fn.fnamemodify(args.filepath, ":.")
      local edit_count = args.edits and #args.edits or 0
      return fmt("Apply %d edit(s) to `%s`?", edit_count, filepath)
    end,

    ---@param self CodeCompanion.Tool.InsertEditIntoFile
    ---@param stdout table|nil The output from the tool
    ---@param meta { tools: table, cmd: table }
    ---@return nil
    success = function(self, stdout, meta)
      if stdout then
        local chat = meta.tools.chat
        local llm_output = vim.iter(stdout):flatten():join("\n")
        chat:add_tool_output(self, llm_output)
      end
    end,
  },
}
