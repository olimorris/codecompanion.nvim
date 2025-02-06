--[[
*Editor Tool*
This tool is used to directly modify the contents of a buffer. It can handle
multiple edits in the same XML block.
--]]

local config = require("codecompanion.config")

local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

local api = vim.api

local diff_started = false

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

  local lines = vim.split(action.code, "\n", { plain = true, trimempty = false })
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
    ---@param actions table The action object
    ---@param input any The output from the previous function call
    ---@return { status: string, msg: string }
    function(self, actions, input)
      ---Run the action
      ---@param action table
      local function run(action)
        local type = action._attr.type

        if not action.buffer then
          return { status = "error", msg = "No buffer number provided by the LLM" }
        end

        local bufnr = tonumber(action.buffer)
        local winnr = ui.buf_get_win(bufnr)

        log:debug("Editor tool request: %s", action)

        if not api.nvim_buf_is_valid(bufnr) then
          return { status = "error", msg = "Invalid buffer number" }
        end

        -- Diff the buffer
        if not diff_started and config.display.diff.enabled and bufnr and vim.bo[bufnr].buftype ~= "terminal" then
          local provider = config.display.diff.provider
          local ok, diff = pcall(require, "codecompanion.providers.diff." .. provider)

          if ok and winnr then
            ---@type CodeCompanion.DiffArgs
            local diff_args = {
              bufnr = bufnr,
              contents = api.nvim_buf_get_lines(bufnr, 0, -1, true),
              filetype = api.nvim_buf_get_option(bufnr, "filetype"),
              winnr = winnr,
            }
            ---@type CodeCompanion.Diff
            diff = diff.new(diff_args)
            keymaps
              .new({
                bufnr = bufnr,
                callbacks = require("codecompanion.strategies.inline.keymaps"),
                data = { diff = diff },
                keymaps = config.strategies.inline.keymaps,
              })
              :set()

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

        return { status = "success", msg = nil }
      end

      local output = {}
      if vim.isarray(actions) then
        for _, v in ipairs(actions) do
          output = run(v)
          if output.status == "error" then
            break
          end
        end
      else
        output = run(actions)
      end

      return output
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
          code = "<![CDATA[    print('Hello World')]]>",
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
          code = "<![CDATA[   function M.capitalize()]]>",
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
          code = "<![CDATA[function M.hello_world()]]>",
        },
      },
    },
  },
  system_prompt = function(schema)
    return string.format(
      [[## Editor Tool

### Purpose:
- Modify the content of a Neovim buffer by adding, updating, or deleting code when explicitly requested.

### When to Use:
- Only invoke the Editor Tool when the user specifically asks (e.g., "can you update the code?" or "update the buffer...").
- Use this tool solely for buffer edit operations. Other file tasks should be handled by the designated tools.

### Execution Format:
- Always return an XML markdown code block.
- Each code operation must:
  - Be wrapped in a CDATA section to preserve special characters (CDATA sections ensure that characters like '<' and '&' are not interpreted as XML markup).
  - Follow the XML schema exactly.
- If several actions (add, update, delete) need to be performed sequentially, combine them in one XML block with separate <action> entries.

### XML Schema:
Each tool invocation should adhere to this structure:

a) **Add Action:**
```xml
%s
```

b) **Update Action:**
```xml
%s
```

c) **Delete Action:**
```xml
%s
```

d) **Multiple Actions:**
```xml
%s
```

### Key Considerations:
- **Safety and Accuracy:** Validate all code updates carefully.
- **CDATA Usage:** Code is wrapped in CDATA blocks to protect special characters and prevent them from being misinterpreted by XML.
- **Tag Order:** Use a consistent order by always listing <start_line> before <end_line> for update and delete actions.
- **Update Rule:** The update action first deletes the range defined in <start_line> to <end_line> (inclusive) and then adds the new code starting from <start_line>.
- **Contextual Assumptions:** If no context is provided, assume that you should update the buffer with the code from your last response.

### Reminder:
- Minimize extra explanations and focus on returning correct XML blocks with properly wrapped CDATA sections.
- Always use the structure above for consistency.]],
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
  handlers = {
    on_exit = function(self)
      deltas = {}
      diff_started = false
    end,
  },
}
