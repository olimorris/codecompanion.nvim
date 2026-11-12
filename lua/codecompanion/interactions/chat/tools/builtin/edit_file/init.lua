local buf_utils = require("codecompanion.utils.buffers")
local edit_target = require("codecompanion.interactions.chat.tools.builtin.edit_file.target")
local replace = require("codecompanion.interactions.chat.tools.builtin.edit_file.replace")

local fmt = string.format

local DESCRIPTION = [[Edit an existing file by replacing an exact string with new text.

- `old_string` must match the file exactly, including whitespace and indentation. If you don't know the file's current content, read it first
- The edit fails if `old_string` appears more than once. Include more surrounding lines to make it unique, or set `replace_all` to change every occurrence
- Keep `old_string` short: usually 2-4 lines that uniquely identify the text to change
- Use `replace_all` to rename a variable or change every occurrence of a string
- To delete text, set `new_string` to an empty string
- To make several changes to a file, call this tool once per change]]

---@class CodeCompanion.Tool.EditFile: CodeCompanion.Tools.Tool
return {
  name = "edit_file",
  kind = "edit",
  cmds = {
    ---@param self CodeCompanion.Tools
    ---@param args { filepath: string, old_string: string, new_string: string, replace_all: boolean|string }
    ---@param opts { output_cb: fun(response: { status: "success"|"error", data: string }) }
    ---@return nil
    function(self, args, opts)
      if type(args.old_string) ~= "string" or type(args.new_string) ~= "string" then
        return opts.output_cb({ status = "error", data = "`old_string` and `new_string` are both required" })
      end

      local found = edit_target.find({
        filepath = args.filepath,
        file_size_limit_mb = self.tool.opts.file_size_limit_mb,
      })
      if found.error then
        return opts.output_cb({ status = "error", data = found.error })
      end
      local target = found.target

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

      return edit_target.review(self, {
        content = edit.content,
        messages = {
          success = fmt("Edited `%s`", target.display_name),
          failure = fmt("Could not edit `%s`", target.display_name),
        },
        output_cb = opts.output_cb,
        target = target,
        tool_name = "edit_file",
      })
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
    cmd_string = function(self, meta)
      return self.args.filepath
    end,

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
      meta.tools.chat:add_tool_output(self, { content = vim.iter(stdout):flatten():join("\n") })
    end,

    ---@param self CodeCompanion.Tool.EditFile
    ---@param stderr table
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return nil
    error = function(self, stderr, meta)
      meta.tools.chat:add_tool_output(self, { content = vim.iter(stderr):flatten():join("\n") })
    end,
  },
}
