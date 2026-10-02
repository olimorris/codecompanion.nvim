local approvals = require("codecompanion.interactions.chat.tools.approvals")
local buf_utils = require("codecompanion.utils.buffers")
local diff = require("codecompanion.interactions.chat.tools.builtin.helpers.diff")
local file_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")
local replace = require("codecompanion.interactions.chat.tools.builtin.edit_file.replace")
local utils = require("codecompanion.utils")

local api = vim.api
local fmt = string.format

local DESCRIPTION = [[Edit an existing file by replacing an exact string with new text.

- `old_string` must match the file exactly, including whitespace and indentation. If you don't know the file's current content, read it first
- The edit fails if `old_string` appears more than once. Include more surrounding lines to make it unique, or set `replace_all` to change every occurrence
- Keep `old_string` short: usually 2-4 lines that uniquely identify the text to change
- Use `replace_all` to rename a variable or change every occurrence of a string
- To delete text, set `new_string` to an empty string
- To make several changes to a file, call this tool once per change]]

---@class CodeCompanion.Tool.EditFile.Target
---@field bufnr? number
---@field content string
---@field display_name string
---@field ft string
---@field path string
---@field write fun(content: string): { error?: string }

---@param filepath string
---@param opts { file_size_limit_mb: number }
---@return { target?: CodeCompanion.Tool.EditFile.Target, error?: string }
local function open_file_for_editing(filepath, opts)
  local path = file_utils.validate_and_normalize_path(filepath)
  if not path or file_utils.is_dir(path) then
    return { error = fmt("`%s` does not exist. Use the path of an existing file", filepath) }
  end

  local stat = vim.uv.fs_stat(path)
  if stat and stat.size > opts.file_size_limit_mb * 1024 * 1024 then
    return {
      error = fmt("`%s` is larger than the %s MB limit for editing", filepath, opts.file_size_limit_mb),
    }
  end

  local ok, original = pcall(file_utils.read, path)
  if not ok then
    log:error("[Edit File Tool] Could not read %s: %s", path, original)
    return { error = fmt("Could not read `%s`", filepath) }
  end

  local target = {
    content = original,
    display_name = vim.fn.fnamemodify(path, ":."),
    ft = vim.filetype.match({ filename = path }) or "text",
    path = path,
    write = function(content)
      local read_ok, current = pcall(file_utils.read, path)
      if not read_ok or current ~= original then
        return { error = "the file changed after the edit was proposed. Read it again and retry" }
      end

      local write_ok, write_err = pcall(file_utils.write_to_path, path, content)
      if not write_ok then
        log:error("[Edit File Tool] Could not write %s: %s", path, write_err)
        return { error = "the file could not be written" }
      end

      local bufnr = vim.fn.bufnr(path)
      if bufnr ~= -1 and api.nvim_buf_is_loaded(bufnr) then
        vim.cmd.checktime(bufnr)
      end

      return {}
    end,
  }

  return { target = target }
end

---Replace the buffer's lines and save it, putting the original lines back if the save fails
---@param bufnr number
---@param opts { lines: string[], original_lines: string[] }
---@return { error?: string }
local function save_buffer(bufnr, opts)
  local was_modified = vim.bo[bufnr].modified
  local set_ok, set_err = pcall(api.nvim_buf_set_lines, bufnr, 0, -1, false, opts.lines)
  if not set_ok then
    log:error("[Edit File Tool] Could not change buffer %d: %s", bufnr, set_err)
    return { error = "the buffer could not be changed. It may not be modifiable" }
  end

  local write_ok, write_err = pcall(api.nvim_buf_call, bufnr, function()
    vim.cmd("silent write")
  end)
  if not write_ok then
    log:error("[Edit File Tool] Could not save buffer %d: %s", bufnr, write_err)
    api.nvim_buf_set_lines(bufnr, 0, -1, false, opts.original_lines)
    vim.bo[bufnr].modified = was_modified
    return { error = "the buffer could not be saved. It may be read-only" }
  end

  return {}
end

---@param bufnr number
---@return { target: CodeCompanion.Tool.EditFile.Target }
local function open_buffer_for_editing(bufnr)
  if not api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
  end
  local path = api.nvim_buf_get_name(bufnr)
  local original_lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local target = {
    bufnr = bufnr,
    content = table.concat(original_lines, "\n"),
    display_name = vim.fn.fnamemodify(path, ":."),
    ft = vim.bo[bufnr].filetype,
    path = path,
    write = function(content)
      if not vim.deep_equal(api.nvim_buf_get_lines(bufnr, 0, -1, false), original_lines) then
        return { error = "the buffer changed after the edit was proposed. Read it again and retry" }
      end

      return save_buffer(bufnr, { lines = vim.split(content, "\n", { plain = true }), original_lines = original_lines })
    end,
  }

  return { target = target }
end

---@param text string
---@return string[]
local function split_lines(text)
  return vim.split((text:gsub("\r\n", "\n")), "\n", { plain = true })
end

---@param from_lines string[]
---@param to_lines string[]
---@return number
local function get_first_changed_line(from_lines, to_lines)
  for i = 1, math.max(#from_lines, #to_lines) do
    if from_lines[i] ~= to_lines[i] then
      return i
    end
  end
  return 1
end

---Show the edit for review and write it once accepted
---@param tools CodeCompanion.Tools
---@param opts { edited: string, output_cb: fun(response: table), target: CodeCompanion.Tool.EditFile.Target }
---@return nil
local function review_edit(tools, opts)
  local target = opts.target
  local from_lines = split_lines(target.content)
  local to_lines = split_lines(opts.edited)

  return diff.review({
    from_lines = from_lines,
    to_lines = to_lines,
    apply = function()
      local written = target.write(opts.edited)
      if written.error then
        return opts.output_cb({
          status = "error",
          data = fmt("Could not edit `%s`: %s", target.display_name, written.error),
        })
      end
      utils.fire("FileEdited", {
        bufnr = target.bufnr,
        line = get_first_changed_line(from_lines, to_lines),
        path = target.path,
        tool = "edit_file",
      })
      opts.output_cb({ status = "success", data = fmt("Edited `%s`", target.display_name) })
    end,
    approved = approvals:is_approved(tools.chat.bufnr, { tool_name = "edit_file" }),
    chat = tools.chat,
    chat_bufnr = tools.chat.bufnr,
    ft = target.ft,
    output_cb = opts.output_cb,
    require_confirmation_after = tools.tool.opts.require_confirmation_after,
    title = target.display_name,
    tool_name = "edit_file",
  })
end

---@class CodeCompanion.Tool.EditFile: CodeCompanion.Tools.Tool
return {
  name = "edit_file",
  cmds = {
    ---@param self CodeCompanion.Tools
    ---@param args { filepath: string, old_string: string, new_string: string, replace_all: boolean|string }
    ---@param opts { output_cb: fun(response: { status: "success"|"error", data: string }) }
    ---@return nil
    function(self, args, opts)
      if type(args.old_string) ~= "string" or type(args.new_string) ~= "string" then
        return opts.output_cb({ status = "error", data = "`old_string` and `new_string` are both required" })
      end

      local bufnr = buf_utils.get_bufnr_from_path(args.filepath)
      local opened = bufnr and open_buffer_for_editing(bufnr)
        or open_file_for_editing(args.filepath, { file_size_limit_mb = self.tool.opts.file_size_limit_mb })
      if opened.error then
        return opts.output_cb({ status = "error", data = opened.error })
      end
      local target = opened.target

      local edit = replace.apply(target.content, {
        old_string = args.old_string,
        new_string = args.new_string,
        -- Weaker models send booleans as strings when the provider doesn't enforce the schema
        replace_all = args.replace_all == true or args.replace_all == "true",
      })
      if edit.error then
        return opts.output_cb({
          status = "error",
          data = fmt("Could not edit `%s`: %s", target.display_name, edit.error),
        })
      end

      return review_edit(self, { edited = edit.content, output_cb = opts.output_cb, target = target })
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "edit_file",
      description = DESCRIPTION,
      parameters = {
        type = "object",
        properties = {
          filepath = {
            type = "string",
            description = "The absolute path to the file to edit",
          },
          old_string = {
            type = "string",
            description = "The exact text to replace",
          },
          new_string = {
            type = "string",
            description = "The text to replace it with. Must be different from `old_string`",
          },
          replace_all = {
            type = "boolean",
            description = "Replace every occurrence of `old_string` instead of requiring a unique match",
          },
        },
        required = { "filepath", "old_string", "new_string", "replace_all" },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  handlers = {
    ---@param self CodeCompanion.Tool.EditFile
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return boolean
    prompt_condition = function(self, meta)
      local require_approval_before = self.opts.require_approval_before or {}
      if buf_utils.get_bufnr_from_path(self.args.filepath) then
        return require_approval_before.buffer == true
      end
      return require_approval_before.file == true
    end,
  },
  output = {
    ---@param self CodeCompanion.Tool.EditFile
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return string
    prompt = function(self, meta)
      return fmt("Edit `%s`?", vim.fn.fnamemodify(self.args.filepath, ":."))
    end,

    ---@param self CodeCompanion.Tool.EditFile
    ---@param stdout table
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return nil
    success = function(self, stdout, meta)
      meta.tools.chat:add_tool_output(self, vim.iter(stdout):flatten():join("\n"), "")
    end,

    ---@param self CodeCompanion.Tool.EditFile
    ---@param stderr table
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return nil
    error = function(self, stderr, meta)
      meta.tools.chat:add_tool_output(self, vim.iter(stderr):flatten():join("\n"))
    end,
  },
}
