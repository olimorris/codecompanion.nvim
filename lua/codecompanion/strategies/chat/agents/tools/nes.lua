local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.Tool.NextEditSuggestion.Args
---@field path string
---@field line integer

---@class CodeCompanion.Tool.NextEditSuggestion: CodeCompanion.Agent.Tool
return {
  name = "nes",
  schema = {
    type = "function",
    ["function"] = {
      name = "nes",
      description = "Suggest a possible position in a file for the next edit.",
      parameters = {
        type = "object",
        properties = {
          path = {
            type = "string",
            description = "The path to the file",
          },
          line = {
            type = "integer",
            description = "Line number for the next edit (1-indexed). Use -1 if you're not sure about it.",
          },
        },
        required = { "path", "line" },
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
- Pass -1 as the line number if you are not sure about the correct line number.
    ]]
  end,

  cmds = {
    ---@param self CodeCompanion.Tool.NextEditSuggestion
    ---@param args CodeCompanion.Tool.NextEditSuggestion.Args
    ---@return {status: "success"|"error", data: string}
    function(self, args, _)
      if type(args.path) == "string" then
        args.path = vim.fs.normalize(args.path)
      end
      local stat = vim.uv.fs_stat(args.path)
      if stat == nil or stat.type ~= "file" then
        return { status = "error", data = "Invalid path: " .. tostring(args.path) }
      end
      vim.cmd("tabnew " .. args.path)
      vim.api.nvim_win_set_cursor(0, { args.line, 0 })
      return { status = "success", data = "Jump successful!" }
    end,
  },
}
