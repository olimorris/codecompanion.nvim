local config = require("codecompanion").config

local keymaps = require("codecompanion.utils.keymaps")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

local api = vim.api

---@class CodeCompanion.Tool
return {
  name = "editor",
  cmds = {
    ---Ensure the final function returns the status and the output
    ---@param self CodeCompanion.Tools The Tools object
    ---@param input any The output from the previous function call
    ---@return table { status: string, output: string }
    function(self, input)
      local diff
      local action = self.tool.request.parameters.inputs
      local lines = vim.split(action.code, "\n", { plain = true, trimempty = false })

      -- Diff the buffer
      if config.opts.diff.enabled then
        local ok
        local provider = config.display.inline.diff.provider
        ok, diff = pcall(require, "codecompanion.helpers.diff." .. provider)

        if ok then
          ---@type CodeCompanion.DiffArgs
          local diff_args = {
            bufnr = tonumber(action.buffer),
            contents = api.nvim_buf_get_lines(self.chat.context.bufnr, 0, -1, true),
            filetype = self.chat.context.filetype,
            winnr = self.chat.context.winnr,
          }
          ---@type CodeCompanion.Diff
          diff = diff.new(diff_args)
          keymaps.set(config.strategies.inline.keymaps, self.chat.context.bufnr, { diff = diff })
        end
      end

      if action.method == "insert" then
        vim.api.nvim_buf_set_lines(
          tonumber(action.buffer),
          tonumber(action.line) - 1,
          tonumber(action.line) - 1,
          false,
          lines
        )
      end
      if action.method == "replace" then
        vim.api.nvim_buf_set_lines(
          tonumber(action.buffer),
          tonumber(action.start_line) - 1,
          tonumber(action.end_line),
          false,
          lines
        )
      end

      return { status = "success", output = nil }
    end,
  },
  schema = {
    {
      name = "editor",
      parameters = {
        inputs = {
          buffer = 1,
          method = "insert",
          line = 203,
          code = "print('Hello World')",
        },
      },
    },
    {
      name = "editor",
      parameters = {
        inputs = {
          buffer = 14,
          method = "replace",
          start_line = 10,
          end_line = 15,
          code = "print('Hello CodeCompanion')",
        },
      },
    },
  },
  system_prompt = function(schema)
    return string.format(
      [[### You have gained access to a new tool!

Name: Editor
Purpose: The tool enables you to update the contents of a Neovim buffer
Why: When you suggest code changes, the user can quickly implement them without having to copy and paste
Usage: To use this tool, you need to return an XML markdown code block (with backticks). With the tool you can insert code at a specific line number and/or replace specific code.

Consider the following example which inserts "Hello World" into a buffer with id 1, at line 203:

```xml
%s
```

Or, Consider the following example which replaces content between the lines 10 and 15 with "Hello CodeCompanion" in a buffer with id 14:

```xml
%s
```

You must:
- Even though you have access to the tool, you are not permitted to use it in all of your responses
- You can only use this tool when the user specifically asks for it in their last message. For example "can you update the code for me?" or "can you insert the code ..."
- Ensure the user has seen your code and approved it before you call the tool
- Ensure the code you're executing will be able to parsed as valid XML]],
      xml2lua.toXml(schema[1], "tool"),
      xml2lua.toXml(schema[2], "tool")
    )
  end,
}
