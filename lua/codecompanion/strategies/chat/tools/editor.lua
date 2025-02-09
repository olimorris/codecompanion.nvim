--[[
*Editor Tool*
This tool is used to directly modify the contents of a buffer. It can handle
multiple edits in the same XML block.
--]]

local config = require("codecompanion.config")

local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

local api = vim.api

local diff_started = false

-- To keep track of the changes made to the buffer, we store them in this table
local deltas = {}
local function add_delta(bufnr, line, delta)
  table.insert(deltas, { bufnr = bufnr, line = line, delta = delta })
end

---Calculate if there is any intersection between the lines
---@param bufnr number
---@param line number
local function intersect(bufnr, line)
  local delta = 0
  for _, v in ipairs(deltas) do
    if bufnr == v.bufnr and line > v.line then
      delta = delta + v.delta
    end
  end
  return delta
end

---Delete lines from the buffer
---@param bufnr number
---@param action table
local function delete(bufnr, action)
  log:debug("[Editor Tool] Deleting code from the buffer")

  local start_line = tonumber(action.start_line)
  assert(start_line, "No start line number provided by the LLM")
  if start_line == 0 then
    start_line = 1
  end

  local end_line = tonumber(action.end_line)
  assert(end_line, "No end line number provided by the LLM")
  if end_line == 0 then
    end_line = 1
  end

  local delta = intersect(bufnr, start_line)

  api.nvim_buf_set_lines(bufnr, start_line + delta - 1, end_line + delta, false, {})
  add_delta(bufnr, start_line, (start_line - end_line - 1))
end

---Add lines to the buffer
---@param bufnr number
---@param action table
local function add(bufnr, action)
  log:debug("[Editor Tool] Adding code to buffer")

  if not action.line and not action.replace then
    assert(false, "No line number or replace request provided by the LLM")
  end

  local start_line
  if action.replace then
    -- Clear the entire buffer
    log:debug("[Editor Tool] Replacing the entire buffer")
    delete(bufnr, { start_line = 1, end_line = api.nvim_buf_line_count(bufnr) })
    start_line = 1
  else
    start_line = action.line and tonumber(action.line) or 1
    if start_line == 0 then
      start_line = 1
    end
  end

  local delta = intersect(bufnr, start_line)

  local lines = vim.split(action.code, "\n", { plain = true, trimempty = false })
  api.nvim_buf_set_lines(bufnr, start_line + delta - 1, start_line + delta - 1, false, lines)

  add_delta(bufnr, start_line, tonumber(#lines))
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

        local bufnr
        if not action.buffer then
          log:debug("[Editor Tool] No buffer number provided by the LLM, using the current buffer")
          bufnr = self.chat.context.bufnr
        end
        bufnr = tonumber(action.buffer)
        assert(bufnr, "No buffer number provided by the LLM")

        log:trace("[Editor Tool] request: %s", action)

        local winnr = ui.buf_get_win(bufnr)
        if not api.nvim_buf_is_valid(bufnr) then
          return { status = "error", msg = "Invalid buffer number" }
        end

        -- Diff the buffer
        if
          not vim.g.codecompanion_auto_tool_mode
          and (not diff_started and config.display.diff.enabled and bufnr and vim.bo[bufnr].buftype ~= "terminal")
        then
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

        -- Automatically save the buffer
        if vim.g.codecompanion_auto_tool_mode then
          log:info("[Editor Tool] Auto-saving buffer")
          api.nvim_buf_call(bufnr, function()
            vim.cmd("silent write")
          end)
        end

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
          _attr = { type = "add" },
          buffer = 1,
          replace = true,
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
          start_line = 50,
          end_line = 99,
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
      [[## Editor Tool (`editor`) - Enhanced Guidelines

### Purpose:
- Modify the content of a Neovim buffer by adding, updating, or deleting code when explicitly requested.

### When to Use:
- Only invoke the Editor Tool when the user specifically asks (e.g., "can you update the code?" or "update the buffer...").
- Use this tool solely for buffer edit operations. Other file tasks should be handled by the designated tools.

### Execution Format:
- Always return an XML markdown code block.
- Always include the buffer number that the user has shared with you, in the `<buffer></buffer>` tag. If the user has not supplied this, prompt them for it.
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

If you'd like to replace the entire buffer's contents, pass in `<replace>true</replace>` in the action:
```xml
%s
```

b) **Update Action:**
```xml
%s
```
- Be sure to include both the start and end lines for the range to be updated.

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
- **Line Numbers:** Note that line numbers are 1-indexed, so the first line is line 1, not line 0.
- **Update Rule:** The update action first deletes the range defined in <start_line> to <end_line> (inclusive) and then adds the new code starting from <start_line>.
- **Contextual Assumptions:** If no context is provided, assume that you should update the buffer with the code from your last response.

### Reminder:
- Minimize extra explanations and focus on returning correct XML blocks with properly wrapped CDATA sections.
- Always use the structure above for consistency.]],
      xml2lua.toXml({ tools = { schema[1] } }), -- Add
      xml2lua.toXml({ tools = { schema[2] } }), -- Add with replace
      xml2lua.toXml({ tools = { schema[3] } }), -- Update
      xml2lua.toXml({ tools = { schema[4] } }), -- Delete
      xml2lua.toXml({ -- Multiple
        tools = {
          tool = {
            _attr = { name = "editor" },
            action = {
              schema[5].action[1],
              schema[5].action[2],
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
