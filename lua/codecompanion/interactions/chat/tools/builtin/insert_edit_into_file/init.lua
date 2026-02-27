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
local constants = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.constants")
local diff_mod = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.diff")
local io_mod = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.io")
local json_repair = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.json_repair")
local match_selector = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.match_selector")
local process_mod = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.process")

local buf_utils = require("codecompanion.utils.buffers")
local file_utils = require("codecompanion.utils.files")

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

---Create response for output_cb
---@param status "success"|"error"
---@param msg string
---@return table
local function make_response(status, msg)
  return { status = status, data = msg }
end

---Extract explanation from action (top level or fallback to first edit)
---@param action table
---@return string
local function extract_explanation(action)
  local explanation = action.explanation or (action.edits and action.edits[1] and action.edits[1].explanation)
  return (explanation and explanation ~= "") and ("\n" .. explanation) or ""
end

---Build a content source for file-based editing
---@param action table
---@return table|nil source, string|nil error
local function make_file_source(action)
  local path = file_utils.validate_and_normalize_path(action.filepath)
  if not path then
    return nil, fmt("Error: Invalid or non-existent filepath `%s`", action.filepath)
  end

  local content, read_err, file_info = io_mod.read_file(path)
  if not content then
    return nil, read_err or "Unknown error reading file"
  end

  if #content > constants.LIMITS.FILE_SIZE_MAX then
    return nil,
      fmt(
        "Error: File too large (%d bytes). Maximum supported size is %d bytes.",
        #content,
        constants.LIMITS.FILE_SIZE_MAX
      )
  end

  local display_name = vim.fn.fnamemodify(action.filepath, ":.")

  return {
    content = content,
    file_info = file_info,
    display_name = display_name,
    ft = vim.filetype.match({ filename = path }) or "text",
    process_opts = { path = path, file_info = file_info, mode = action.mode },
    write = function(new_content)
      return io_mod.write_file(path, new_content, file_info)
    end,
  }
end

---Build a content source for buffer-based editing
---@param bufnr number
---@param action table
---@return table source
local function make_buffer_source(bufnr, action)
  if not api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
  end

  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")
  local buffer_name = api.nvim_buf_get_name(bufnr)
  local display_name = buffer_name ~= "" and vim.fn.fnamemodify(buffer_name, ":.") or fmt("buffer %d", bufnr)

  local file_info = {
    has_trailing_newline = content:match("\n$") ~= nil,
    is_empty = content == "",
  }

  return {
    content = content,
    file_info = file_info,
    display_name = display_name,
    ft = vim.bo[bufnr].filetype or "text",
    process_opts = { buffer = bufnr, file_info = file_info, mode = action.mode },
    write = function(new_content)
      local new_lines = vim.split(new_content, "\n", { plain = true })
      api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
      api.nvim_buf_call(bufnr, function()
        vim.cmd("silent write")
      end)
      return true, nil
    end,
  }
end

---Execute an edit operation against a content source
---@param source table Content source from make_file_source or make_buffer_source
---@param action table
---@param opts table
local function execute_edit(source, action, opts)
  if type(action.edits) == "string" then
    local ok, parsed = pcall(vim.json.decode, action.edits)
    if ok and type(parsed) == "table" then
      action.edits = parsed
    end
  end

  local edit = process_mod.process_edits(source.content, action.edits, source.process_opts)

  if not edit.success then
    local error_message = match_selector.format_helpful_error(edit, action.edits)
    return opts.output_cb(make_response("error", error_message))
  end

  local success_msg = fmt("Edited `%s`%s", source.display_name, extract_explanation(action))

  return diff_mod.approve_and_diff({
    from_lines = vim.split(source.content, "\n", { plain = true }),
    to_lines = vim.split(edit.content, "\n", { plain = true }),
    apply_fn = function()
      local write_ok, write_err = source.write(edit.content)
      if not write_ok then
        return opts.output_cb(make_response("error", fmt("Error writing to `%s`: %s", source.display_name, write_err)))
      end
      opts.output_cb(make_response("success", success_msg))
    end,
    approved = approvals:is_approved(opts.chat_bufnr, { tool_name = "insert_edit_into_file" }),
    chat_bufnr = opts.chat_bufnr,
    ft = source.ft,
    output_cb = opts.output_cb,
    require_confirmation_after = opts.tool_opts.require_confirmation_after,
    success_msg = success_msg,
    title = source.display_name,
  })
end

---@class CodeCompanion.Tool.InsertEditIntoFile: CodeCompanion.Tools.Tool
return {
  name = "insert_edit_into_file",
  cmds = {
    ---Execute the edit tool commands
    ---@param self CodeCompanion.Tools
    ---@param args table The arguments from the LLM's tool call
    ---@param opts {}
    ---@return nil|table
    function(self, args, opts)
      if args.edits then
        local fixed_args, error_msg = json_repair.fix_edits(args)
        if not fixed_args then
          return opts.output_cb(make_response("error", fmt("Invalid edits format: %s", error_msg)))
        end
        args = fixed_args
      end

      local bufnr = buf_utils.get_bufnr_from_path(args.filepath)
      local source, source_err

      if bufnr then
        source = make_buffer_source(bufnr, args)
      else
        source, source_err = make_file_source(args)
        if not source then
          return opts.output_cb(make_response("error", source_err))
        end
      end

      return execute_edit(source, args, {
        chat_bufnr = self.chat.bufnr,
        output_cb = opts.output_cb,
        tool_opts = self.tool.opts,
      })
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
            description = "The absolute path to the file to edit, including its filename and extension",
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
      local display_path = vim.fn.fnamemodify(args.filepath, ":.")
      local edit_count = args.edits and #args.edits or 0
      return fmt("Apply %d edit(s) to `%s`?", edit_count, display_path)
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
