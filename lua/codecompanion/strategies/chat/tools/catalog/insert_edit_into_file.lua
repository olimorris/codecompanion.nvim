local Path = require("plenary.path")
local buffers = require("codecompanion.utils.buffers")
local codecompanion = require("codecompanion")
local config = require("codecompanion.config")
local diff = require("codecompanion.strategies.chat.tools.catalog.helpers.diff")
local log = require("codecompanion.utils.log")
local patch = require("codecompanion.strategies.chat.tools.catalog.helpers.patch") ---@type CodeCompanion.Patch
local ui = require("codecompanion.utils.ui")
local wait = require("codecompanion.strategies.chat.tools.catalog.helpers.wait")

local api = vim.api
local fmt = string.format

local PROMPT = [[<editFileInstructions>
Before editing a file, ensure you have its content via the provided context or read_file tool.
Use the insert_edit_into_file tool to modify files.
NEVER show the code edits to the user - only call the tool. The system will apply and display the edits.
For each file, give a short description of what needs to be edited, then use the insert_edit_into_file tools. You can use the tool multiple times in a response, and you can keep writing text after using a tool.
The insert_edit_into_file tool is very smart and can understand how to apply your edits to the user's files, you just need to follow the patch format instructions carefully and to the letter.

## Patch Format
]] .. patch.prompt .. [[
The system uses fuzzy matching and confidence scoring so focus on providing enough context to uniquely identify the location.
</editFileInstructions>]]

---Resolve the patching algorithm module used to apply the edits to a file
---@param algorithm string|table|function The patch configuration, can be a module path, a table, or a function that returns a table
---@return CodeCompanion.Patch The resolved patch module
local function resolve_patch_module(algorithm)
  if type(algorithm) == "table" then
    return algorithm --[[@as CodeCompanion.Patch]]
  end
  if type(algorithm) == "function" then
    return algorithm() --[[@as CodeCompanion.Patch]]
  end

  -- Try as a local module
  local ok, module = pcall(require, "codecompanion." .. algorithm)
  if ok then
    return module --[[@as CodeCompanion.Patch]]
  end

  -- Try as file path
  local file_module, _ = loadfile(algorithm)
  if file_module then
    return file_module() --[[@as CodeCompanion.Patch]]
  end

  error(string.format("Could not resolve the patch algorithm module: %s", algorithm))
end

---Edit code in a file
---@param action {filepath: string, code: string, explanation: string} The arguments from the LLM's tool call
---@return string|nil, string|nil
local function edit_file(action)
  local filepath = vim.fs.joinpath(vim.fn.getcwd(), action.filepath)
  local p = Path:new(filepath)
  p.filename = p:expand()

  if not p:exists() or not p:is_file() then
    return nil, fmt("Error editing `%s`\nFile does not exist or is not a file", action.filepath)
  end

  -- 1. extract list of edits from the code
  local raw = action.code or ""
  local edits, had_begin_end_markers, parse_error = patch.parse_edits(raw)

  -- 2. read file into lines
  local content = p:read()
  local lines = vim.split(content, "\n", { plain = true })

  -- 3. apply edits
  local all_errors = {}
  if parse_error then
    table.insert(all_errors, parse_error)
  end

  for i, edit in ipairs(edits) do
    local new_lines, error_msg = patch.apply(lines, edit)
    if error_msg then
      table.insert(all_errors, fmt("Edit %d: %s", i, error_msg))
      if not had_begin_end_markers then
        table.insert(all_errors, "Hint: Try wrapping your patch in *** Begin Patch / *** End Patch markers")
      end
    elseif new_lines then
      lines = new_lines
    else
      table.insert(all_errors, fmt("Edit %d: Unknown error applying patch", i))
    end
  end

  -- Return errors
  if #all_errors > 0 then
    return nil, table.concat(all_errors, "\n")
  end

  -- 4. write back
  p:write(table.concat(lines, "\n"), "w")

  -- 5. refresh the buffer if the file is open
  local bufnr = vim.fn.bufnr(p.filename)
  if bufnr ~= -1 and api.nvim_buf_is_loaded(bufnr) then
    api.nvim_command("checktime " .. bufnr)
  end
  return fmt(
    [[Edited `%s`
%s]],
    action.filepath,
    action.explanation
  )
end

---Edit code in a buffer
---@param bufnr number The buffer number to edit
---@param chat_bufnr number The chat buffer number
---@param action {filepath: string, code: string, explanation: string} The arguments from the LLM's tool call
---@param output_handler function The callback to call when done
---@param opts? table Additional options
---@return string|nil, string|nil
local function edit_buffer(bufnr, chat_bufnr, action, output_handler, opts)
  opts = opts or {}

  local should_diff
  local diff_id = math.random(10000000)
  local original_content = nil
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  -- keep original content copy before applying changes
  if diff.should_create(bufnr) then
    original_content = vim.deepcopy(lines)
  else
  end

  -- Capture original content for edit tracking if not already captured
  if not original_content then
    original_content = vim.deepcopy(lines)
  end
  -- Parse and apply patches to buffer
  local raw = action.code or ""
  local edits, had_begin_end_markers, parse_error = patch.parse_edits(raw)
  -- Apply each edit
  local start_line = nil
  local all_errors = {}

  if parse_error then
    table.insert(all_errors, parse_error)
  end

  for i, edit in ipairs(edits) do
    log:debug("[InsertEdit] Applying buffer edit %d/%d", i, #edits)
    local new_lines, error_msg = patch.apply(lines, edit)
    if error_msg then
      log:error("[InsertEdit] Buffer edit %d failed: %s", i, error_msg)
      table.insert(all_errors, fmt("Edit %d: %s", i, error_msg))
      if not had_begin_end_markers then
        table.insert(all_errors, "Hint: Try wrapping your patch in *** Begin Patch / *** End Patch markers")
      end
    elseif new_lines then
      if not start_line then
        start_line = patch.start_line(lines, edit)
        log:debug("[InsertEdit] Buffer edit start line: %d", start_line or -1)
      end
      log:debug("[InsertEdit] Buffer edit %d successful, new line count: %d", i, #new_lines)
      lines = new_lines
    else
      log:error("[InsertEdit] Buffer edit %d: Unknown error applying patch", i)
      table.insert(all_errors, fmt("Edit %d: Unknown error applying patch", i))
    end
  end

  if #all_errors > 0 then
    local error_output = table.concat(all_errors, "\n")
    log:error("[InsertEdit] Buffer edit failed with %d errors", #all_errors)
    return output_handler({
      status = "error",
      data = error_output,
    })
  end

  log:debug("[InsertEdit] All buffer edits applied successfully, final line count: %d", #lines)

  -- Update the buffer with the edited code
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  log:debug("[InsertEdit] Buffer content updated")

  -- Create diff with original content
  if original_content then
    log:debug("[InsertEdit] Creating diff with original content (%d lines)", #original_content)
    should_diff = diff.create(bufnr, diff_id, {
      original_content = original_content,
    })
    if should_diff then
      log:debug("[InsertEdit] Diff created successfully with ID: %s", diff_id)
    else
      log:warn("[InsertEdit] Diff creation returned nil")
    end
  else
    log:debug("[InsertEdit] No original content captured, skipping diff creation")
  end

  -- Scroll to the editing location
  if start_line then
    log:debug("[InsertEdit] Scrolling to line %d", start_line)
    ui.scroll_to_line(bufnr, start_line)
  end

  -- Auto-save if enabled
  if vim.g.codecompanion_auto_tool_mode then
    log:info("[InsertEdit] Auto-saving buffer %d", bufnr)
    api.nvim_buf_call(bufnr, function()
      vim.cmd("silent write")
    end)
  end

  local success = {
    status = "success",
    data = fmt("Edited `%s`\n%s", action.filepath, action.explanation),
  }

  if should_diff and opts.user_confirmation then
    log:debug("[InsertEdit] Setting up diff approval workflow")
    local accept = config.strategies.inline.keymaps.accept_change.modes.n
    local reject = config.strategies.inline.keymaps.reject_change.modes.n

    local wait_opts = {
      chat_bufnr = chat_bufnr,
      notify = config.display.icons.warning .. " Waiting for diff approval ...",
      sub_text = fmt("`%s` - Accept edits / `%s` - Reject edits", accept, reject),
    }

    -- Wait for the user to accept or reject the edit
    return wait.for_decision(diff_id, { "CodeCompanionDiffAccepted", "CodeCompanionDiffRejected" }, function(result)
      local response
      if result.accepted then
        log:info("[InsertEdit] User accepted changes")
        -- Save the buffer
        pcall(function()
          api.nvim_buf_call(bufnr, function()
            vim.cmd("silent! w")
          end)
        end)
        response = success
      else
        log:info("[InsertEdit] User rejected changes")
        response = {
          status = "error",
          data = result.timeout and "User failed to accept the edits in time" or "User rejected the edits",
        }
      end
      -- NOTE: This is required to ensure folding works for chat buffers that aren't visible
      codecompanion.restore(chat_bufnr)
      return output_handler(response)
    end, wait_opts)
  else
    log:debug("[InsertEdit] No user confirmation needed, returning success")
  end

  return output_handler(success)
end

---@class CodeCompanion.Tool.InsertEditIntoFile: CodeCompanion.Tools.Tool
return {
  name = "insert_edit_into_file",
  cmds = {
    ---Execute the edit commands
    ---@param self CodeCompanion.Tools
    ---@param args table The arguments from the LLM's tool call
    ---@param input? any The output from the previous function call
    ---@param output_handler function Async callback for completion
    ---@return nil
    function(self, args, input, output_handler)
      log:debug("[InsertEdit] Tool execution started for: %s", args.filepath)

      local bufnr = buffers.get_bufnr_from_filepath(args.filepath)
      if bufnr then
        return edit_buffer(bufnr, self.chat.bufnr, args, output_handler, self.tool.opts)
      else
        local success_msg, error_msg = edit_file(args)
        if error_msg then
          return output_handler({ status = "error", data = error_msg })
        end
        return output_handler({ status = "success", data = success_msg })
      end
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "insert_edit_into_file",
      description = "Insert new code or modify existing code in a file. Use this tool once per file that needs to be modified, even if there are multiple edits for a file. The system is very smart and can understand how to apply your edits to the user's files if you follow the instructions.",
      parameters = {
        type = "object",
        properties = {
          explanation = {
            type = "string",
            description = "A short explanation of the code edit being made",
          },
          filepath = {
            type = "string",
            description = "The path to the file to edit, including its filename and extension",
          },
          code = {
            type = "string",
            description = "The code which follows the patch format",
          },
        },
        required = {
          "explanation",
          "filepath",
          "code",
        },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  system_prompt = PROMPT,
  handlers = {
    ---The handler to determine whether to prompt the user for approval
    ---@param self CodeCompanion.Tool.InsertEditIntoFile
    ---@param tools CodeCompanion.Tools
    ---@param config table The tool configuration
    ---@return boolean
    prompt_condition = function(self, tools, config)
      local opts = config["insert_edit_into_file"].opts or {}

      local args = self.args
      local bufnr = buffers.get_bufnr_from_filepath(args.filepath)
      if bufnr then
        if opts.requires_approval.buffer then
          return true
        end
        return false
      end

      if opts.requires_approval.file then
        return true
      end
      return false
    end,

    ---Resolve the patch algorithm to use
    ---@param tool CodeCompanion.Tool.InsertEditIntoFile
    ---@param tools CodeCompanion.Tools The tool object
    setup = function(tool, tools)
      patch = resolve_patch_module(tool.opts.patching_algorithm)
    end,

    ---@param tools CodeCompanion.Tools The tool object
    ---@return nil
    on_exit = function(tools)
      log:trace("[Insert Edit Into File Tool] on_exit handler executed")
    end,
  },
  output = {
    ---The message which is shared with the user when asking for their approval
    ---@param self CodeCompanion.Tool.InsertEditIntoFile
    ---@param tools CodeCompanion.Tools
    ---@return nil|string
    prompt = function(self, tools)
      local args = self.args
      local filepath = vim.fn.fnamemodify(args.filepath, ":.")
      return fmt("Edit the file at %s?", filepath)
    end,

    ---@param self CodeCompanion.Tool.InsertEditIntoFile
    ---@param tools CodeCompanion.Tools
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, tools, cmd, stdout)
      local llm_output = vim.iter(stdout):flatten():join("\n")
      tools.chat:add_tool_output(self, llm_output)
    end,

    ---@param self CodeCompanion.Tool.InsertEditIntoFile
    ---@param tools CodeCompanion.Tools
    ---@param cmd table
    ---@param stderr table The error output from the command
    error = function(self, tools, cmd, stderr)
      local chat = tools.chat
      local args = self.args
      local errors = vim.iter(stderr):flatten():join("\n")
      log:error("[InsertEdit] Tool execution error for %s: %s", args.filepath, errors)

      local error_output = fmt(
        [[Error editing `%s`
%s]],
        args.filepath,
        errors
      )

      local llm_error_output = fmt(
        [[%s

**Troubleshooting tips:**
- Ensure your patch uses the correct format with Begin/End markers
- Check that the context lines exactly match the file content
- Verify indentation and whitespace match precisely
- Try providing more unique context to improve matching confidence]],
        error_output
      )

      chat:add_tool_output(self, llm_error_output, error_output)
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tool.InsertEditIntoFile
    ---@param tools CodeCompanion.Tools
    ---@param cmd table
    ---@return nil
    rejected = function(self, tools, cmd)
      local chat = tools.chat
      chat:add_tool_output(self, fmt("User rejected to edit `%s`", self.args.filepath))
    end,
  },
}
