local config = require("codecompanion.config")

local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils.util")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

local api = vim.api

---Sometimes the LLM will insert new lines as `\n` which are then escaped by
---the XML library. This function unescapes them
---@param str string
---@return string
local function unescape_breaks(str)
  if not str then
    return str
  end
  return str:gsub("\\n", "\n")
end

-- To keep track of the changes made to the buffer, we store them in this table
local deltas = {}
local function add_delta(bufnr, line, delta)
  table.insert(deltas, { bufnr = bufnr, line = line, delta = delta })
end
local function intersect(bufnr, line)
  local delta = 0
  for _, v in ipairs(deltas) do
    if bufnr == v.bufnr and line > v.line then
      delta = delta + v.delta
    end
  end
  return delta
end

local function add(bufnr, action)
  log:trace("Adding code to buffer")
  local start_line = tonumber(action.line)
  local delta = intersect(bufnr, start_line)

  local lines = vim.split(unescape_breaks(action.code), "\n", { plain = true, trimempty = false })
  api.nvim_buf_set_lines(bufnr, start_line + delta - 1, start_line + delta - 1, false, lines)

  add_delta(bufnr, start_line, tonumber(#lines))
end

local function delete(bufnr, action)
  log:trace("Deleting code from the buffer")
  local start_line = tonumber(action.start_line)
  local end_line = tonumber(action.end_line)
  local delta = intersect(bufnr, start_line)

  api.nvim_buf_set_lines(bufnr, start_line + delta - 1, end_line + delta, false, {})
  add_delta(bufnr, start_line, (start_line - end_line - 1))
end

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
          add(bufnr, action)
        elseif type == "delete" then
          delete(bufnr, action)
        elseif type == "update" then
          delete(bufnr, action)

          action.line = action.start_line
          add(bufnr, action)
        end

        --TODO: Scroll to buffer and the new lines
      end

      local action = self.tool.request.action
      if util.is_array(action) then
        for _, v in ipairs(action) do
          run(v)
        end
      else
        run(action)
      end

      deltas = {}
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
          code = "    print('Hello World')",
        },
      },
    },
    {
      tool = {
        _attr = { name = "editor" },
        action = {
          _attr = { type = "update" },
          buffer = 10,
          start_line = 199,
          end_line = 199,
          code = "   function M.capitalize()",
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
    {
      tool = { name = "editor" },
      action = {
        {
          _attr = { type = "delete" },
          buffer = 5,
          start_line = 13,
          end_line = 13,
        },
        {
          _attr = { type = "add" },
          buffer = 5,
          line = 20,
          code = "function M.hello_world()",
        },
      },
    },
  },
  system_prompt = function(schema)
    return string.format(
      [[### Editor Tool

1. **Purpose**: Update the contents of a Neovim buffer

2. **Usage**: Return an XML markdown code block for add, update, or delete operations.

3. **Key Points**:
  - **Only use when prompted** by user (e.g., "can you update the code?")
  - Ensure XML is **valid and follows the schema**
  - **Include indentation** in your code
  - **Don't escape** special characters

4. **Actions**:

a) Add:

```xml
%s
```

b) Update:

```xml
%s
```

c) Delete:

```xml
%s
```

5. **Multiple Actions**: Combine actions in one response if needed:

```xml
%s
```

6. **Note**:
  - For the delete action, the <start_line> and <end_line> tags are inclusive
  - The update action first deletes the range in <start_line> and <end_line> (inclusively) and then adds new code from the <start_line>
  - Account for comment blocks and indentation in your code
  - If the user supplies no context, it can be assumed that they would like you to update the buffer with the code from your last response

Remember: Minimize explanations unless prompted. Focus on generating correct XML.]],
      xml2lua.toXml({ tools = { schema[1] } }),
      xml2lua.toXml({ tools = { schema[2] } }),
      xml2lua.toXml({ tools = { schema[3] } }),
      xml2lua.toXml({
        tools = {
          tool = {
            _attr = { name = "editor" },
            action = {
              schema[4].action[1],
              schema[4].action[2],
            },
          },
        },
      })
    )
  end,
}
