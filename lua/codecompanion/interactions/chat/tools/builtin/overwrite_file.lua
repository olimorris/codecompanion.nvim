local edit_target = require("codecompanion.interactions.chat.tools.builtin.edit_file.target")
local helpers = require("codecompanion.interactions.chat.tools.builtin.helpers")

local fmt = string.format

local DESCRIPTION = [[Replace the entire content of an existing file.

- Use this when rewriting most or all of a file. For targeted changes, use `edit_file` instead
- `content` replaces everything in the file, so include every line that should remain
- Read the file first if you haven't already, so nothing is lost by accident
- The file must already exist. To make a new file, use `create_file`]]

---Match the model's line endings to the target, which arrive as LF regardless of the file
---@param opts { content: string, target: CodeCompanion.Tool.EditFile.Target }
---@return string
local function match_line_endings(opts)
  local content = opts.content:gsub("\r\n", "\n")
  if opts.target.bufnr then
    -- A buffer adds the final newline itself when saved, so keeping it would leave a blank last line
    return (content:gsub("\n$", ""))
  end
  if opts.target.content:find("\r\n", 1, true) then
    return (content:gsub("\n", "\r\n"))
  end
  return content
end

---@class CodeCompanion.Tool.OverwriteFile: CodeCompanion.Tools.Tool
return {
  name = "overwrite_file",
  kind = "edit",
  cmds = {
    ---@param self CodeCompanion.Tools
    ---@param args { filepath: string, content: string }
    ---@param opts { output_cb: fun(response: { status: "success"|"error", data: string }) }
    ---@return nil
    function(self, args, opts)
      if type(args.content) ~= "string" then
        return opts.output_cb({ status = "error", data = "`content` is required" })
      end

      local opened = edit_target.open({
        filepath = args.filepath,
        file_size_limit_mb = self.tool.opts.file_size_limit_mb,
        must_exist = true,
      })
      if opened.error then
        return opts.output_cb({ status = "error", data = opened.error })
      end
      local target = opened.target

      return edit_target.review(self, {
        content = match_line_endings({ content = args.content, target = target }),
        messages = {
          success = fmt("Overwrote `%s`", target.display_name),
          failure = fmt("Could not overwrite `%s`", target.display_name),
        },
        output_cb = opts.output_cb,
        target = target,
        tool_name = "overwrite_file",
      })
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "overwrite_file",
      description = DESCRIPTION,
      parameters = {
        type = "object",
        properties = {
          filepath = {
            type = "string",
            description = "The absolute path to the file to overwrite",
          },
          content = {
            type = "string",
            description = "The new content of the whole file",
          },
        },
        required = { "filepath", "content" },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  output = {
    ---@param self CodeCompanion.Tool.OverwriteFile
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return string
    cmd_string = function(self, meta)
      return self.args.filepath
    end,

    ---@param self CodeCompanion.Tool.OverwriteFile
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return string
    prompt = function(self, meta)
      return fmt("Overwrite `%s`?", vim.fn.fnamemodify(self.args.filepath, ":."))
    end,

    ---@param self CodeCompanion.Tool.OverwriteFile
    ---@param stdout table
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return nil
    success = function(self, stdout, meta)
      meta.tools.chat:add_tool_output(self, { content = vim.iter(stdout):flatten():join("\n") })
    end,

    ---@param self CodeCompanion.Tool.OverwriteFile
    ---@param stderr table
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return nil
    error = function(self, stderr, meta)
      meta.tools.chat:add_tool_output(self, { content = vim.iter(stderr):flatten():join("\n") })
    end,

    ---@param self CodeCompanion.Tool.OverwriteFile
    ---@param meta { tools: CodeCompanion.Tools, cmd: string, opts: table }
    ---@return nil
    rejected = function(self, meta)
      meta = vim.tbl_extend("force", { message = "The user rejected overwriting the file" }, meta or {})
      helpers.rejected(self, meta)
    end,
  },
}
