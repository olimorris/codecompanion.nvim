local log = require("codecompanion.utils.log")

---@class CodeCompanion.Tool.NextEditSuggestion.Args
---@field filepath string
---@field line integer

---@alias jump_action fun(path: string):integer?

---@class CodeCompanion.Tool.NextEditSuggestion: CodeCompanion.Agent.Tool
return {
  opts = {
    ---@type jump_action|string
    jump_action = require("codecompanion.utils.ui").tabnew_reuse,
  },
  name = "next_edit_suggestion",
  schema = {
    type = "function",
    ["function"] = {
      name = "next_edit_suggestion",
      description = "Suggest a possible position in a file for the next edit.",
      parameters = {
        type = "object",
        properties = {
          filepath = {
            type = "string",
            description = "The relative path to the file to edit, including its filename and extension.",
          },
          line = {
            type = "integer",
            description = "Line number for the next edit (0-based). Use -1 if you're not sure about it.",
          },
        },
        required = { "filepath", "line" },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  system_prompt = function(_)
    return [[# Next Edit Suggestion Tool

## CONTEXT
When you suggest a change to the codebase, you may call this tool to jump to the position in the file.

## OBJECTIVE
- Follow the tool's schema.
- Respond with a single command, per tool execution.

## RESPONSE
- Only use this tool when you have been given paths to the files
- DO NOT make up paths that you are not given
- Only use this tool when there's an unambiguous position to jump to
- If there are multiple possible edits, ask the users to make a choice before jumping
- Pass -1 as the line number if you are not sure about the correct line number
- Consider the paths as **CASE SENSITIVE**
    ]]
  end,

  cmds = {
    ---@param self CodeCompanion.Agent
    ---@param args CodeCompanion.Tool.NextEditSuggestion.Args
    ---@return {status: "success"|"error", data: string}
    function(self, args, _)
      if type(args.filepath) == "string" then
        args.filepath = vim.fs.normalize(args.filepath)
      end
      local stat = vim.uv.fs_stat(args.filepath)
      if stat == nil or stat.type ~= "file" then
        log:error("failed to jump to %s", args.filepath)
        if stat then
          log:error("file stat:\n%s", vim.inspect(stat))
        end
        return { status = "error", data = "Invalid path: " .. tostring(args.filepath) }
      end

      if type(self.tool.opts.jump_action) == "string" then
        local action_command = self.tool.opts.jump_action
        ---@type jump_action
        self.tool.opts.jump_action = function(path)
          vim.cmd(action_command .. " " .. path)
          return vim.api.nvim_get_current_win()
        end
      end
      local winnr = self.tool.opts.jump_action(args.filepath)
      if args.line >= 0 and winnr then
        local ok = pcall(vim.api.nvim_win_set_cursor, winnr, { args.line + 1, 0 })
        if not ok then
          local bufnr = vim.api.nvim_win_get_buf(winnr)
          return {
            status = "error",
            data = string.format(
              "The jump to the file was successful, but This file only has %d lines. Unable to jump to line %d",
              vim.api.nvim_buf_line_count(bufnr),
              args.line
            ),
          }
        end
      end
      return { status = "success", data = "Jump successful!" }
    end,
  },
}
