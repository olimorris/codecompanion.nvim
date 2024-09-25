local config = require("codecompanion").config

local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils.util")
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
      local diff_started = false

      ---Run the action
      ---@param action table
      local function run(action)
        local type = action._attr.type
        local bufnr = tonumber(action.buffer)
        local winnr = ui.buf_get_win(bufnr)

        log:debug("Editor tool request: %s", action)

        if not api.nvim_buf_is_valid(bufnr) then
          return { status = "error", output = "Invalid buffer number" }
        end

        -- Diff the buffer
        if config.display.diff.enabled and bufnr and vim.bo[bufnr].buftype ~= "terminal" then
          local ok
          local provider = config.display.diff.provider
          ok, diff = pcall(require, "codecompanion.helpers.diff." .. provider)

          if ok and winnr and not diff_started then
            ---@type CodeCompanion.DiffArgs
            local diff_args = {
              bufnr = bufnr,
              contents = api.nvim_buf_get_lines(bufnr, 0, -1, true),
              filetype = api.nvim_buf_get_option(bufnr, "filetype"),
              winnr = winnr,
            }
            ---@type CodeCompanion.Diff
            diff = diff.new(diff_args)
            keymaps.set(config.strategies.inline.keymaps, bufnr, { diff = diff })
            diff_started = true
          end
        end

        if type == "add" then
          log:trace("Adding code to buffer")
          local lines = vim.split(action.code, "\n", { plain = true, trimempty = false })
          api.nvim_buf_set_lines(bufnr, tonumber(action.line), tonumber(action.line), false, lines)
        end
        if type == "delete" then
          log:trace("Deleting code from the buffer")
          api.nvim_buf_set_lines(bufnr, tonumber(action.start_line) - 1, tonumber(action.end_line), false, {})
        end

        --TODO: Scroll to new function
      end

      local action = self.tool.request.action
      if util.is_array(action) then
        for _, v in ipairs(action) do
          run(v)
        end
      else
        run(action)
      end

      return { status = "success", output = nil }
    end,
  },
  schema = {
    {
      tool = {
        _attr = { name = "editor" },
        action = {
          _attr = { type = "add" },
          buffer = 1,
          line = 203,
          code = "print('Hello World')",
        },
      },
    },
    {
      tool = {
        _attr = { name = "editor" },
        action = {
          _attr = { type = "delete" },
          buffer = 14,
          start_line = 10,
          end_line = 15,
        },
      },
    },
  },
  system_prompt = function(schema)
    return string.format(
      [[### You have gained access to a new tool!

Name: Editor
Purpose: The tool enables you to update the contents of a Neovim buffer
Why: When you suggest code changes in your response, the user can quickly implement them without having to copy and paste
Usage: To use this tool, you need to return an XML markdown code block (with backticks) which follows one of the defined schemas below. With the tool you can add code at a specific line number in the buffer and/or delete code between specific lines:

Consider the following example which adds the code "Hello World" into a buffer with id 1, at line 203:

```xml
%s
```

Or, Consider the following example which deletes code between the lines 10 and 15 in a buffer with id 14:

```xml
%s
```

You can even combine multiple actions in a single response:

```xml
%s
```

You must:
- Only use the tool when prompted by the user. For example "can you update the code for me?" or "can you add ..."
- Be mindful that you may not be required to use the tool in all of your responses
- Ensure the XML markdown code block is valid and follows the schema]],
      xml2lua.toXml({ tools = { schema[1] } }),
      xml2lua.toXml({ tools = { schema[2] } }),
      xml2lua.toXml({
        tools = {
          tool = {
            _attr = { name = "editor" },
            action = {
              schema[1].tool.action,
              schema[2].tool.action,
            },
          },
        },
      })
    )
  end,
}
