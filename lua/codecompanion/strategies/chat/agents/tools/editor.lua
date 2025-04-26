--[[
*Editor Tool*
This tool is used to directly modify the contents of a buffer. It can handle
multiple edits in the same XML block.
--]]

local config = require("codecompanion.config")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")

local api = vim.api
local fmt = string.format

local diff_started = false

-- To keep track of the changes made to the buffer, we store them in this table
local deltas = {}

---Add a delta to the list of deltas
---@param bufnr number
---@param line number
---@param delta number
---@return nil
local function add_delta(bufnr, line, delta)
  table.insert(deltas, { bufnr = bufnr, line = line, delta = delta })
end

---Calculate if there is any intersection between the lines
---@param bufnr number
---@param line number
---@return number
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
---@param args {buffer: number, start_line: number, end_line: number}
---@return nil
local function delete(args)
  log:debug("[Editor Tool] Deleting code from the buffer")

  local start_line = tonumber(args.start_line)
  if not start_line then
    return { status = "error", data = "No start line number provided by the LLM" }
  end
  if start_line == 0 then
    start_line = 1
  end

  local end_line = tonumber(args.end_line)
  if not end_line then
    return { status = "error", data = "No end line number provided by the LLM" }
  end
  if end_line == 0 then
    end_line = 1
  end

  local delta = intersect(args.buffer, start_line)

  api.nvim_buf_set_lines(args.buffer, start_line + delta - 1, end_line + delta, false, {})
  add_delta(args.buffer, start_line, (start_line - end_line - 1))
  return { status = "success", data = nil }
end

---Add lines to the buffer
---@param args {buffer: number, start_line: number, code: string}
---@return nil
local function add(args)
  log:debug("[Editor Tool] Adding code to buffer")

  if not args.start_line then
    return { status = "error", data = "No line number or replace request provided by the LLM" }
  end

  local start_line = tonumber(args.start_line)
  if not start_line then
    return { status = "error", data = "No line number provided by the LLM" }
  end
  if start_line == 0 then
    start_line = 1
  end

  local delta = intersect(args.buffer, start_line)

  local lines = vim.split(args.code, "\n", { plain = true, trimempty = false })
  api.nvim_buf_set_lines(args.buffer, start_line + delta - 1, start_line + delta - 1, false, lines)

  add_delta(args.buffer, start_line, #lines)
  return { status = "success", data = nil }
end

---@class CodeCompanion.Tool.Editor: CodeCompanion.Agent.Tool
return {
  name = "editor",
  opts = {
    use_handlers_once = true,
  },
  cmds = {
    ---Ensure the final function returns the status and the output
    ---@param self CodeCompanion.Tool.Editor The Editor tool
    ---@param args table The arguments from the LLM's tool call
    ---@param input? any The output from the previous function call
    ---@return nil|{ status: "success"|"error", data: string }
    function(self, args, input)
      ---Run the action
      ---@param run_args {buffer: number, action: string, code: string, start_line: number, end_line: number}
      ---@return { status: "success"|"error", data: string }
      local function run(run_args)
        local winnr = ui.buf_get_win(run_args.buffer)
        -- log:trace("[Editor Tool] request: %s", run_args)

        -- Diff the buffer
        if
          not vim.g.codecompanion_auto_tool_mode
          and (
            not diff_started
            and config.display.diff.enabled
            and run_args.buffer
            and vim.bo[run_args.buffer].buftype ~= "terminal"
          )
        then
          local provider = config.display.diff.provider
          local ok, diff = pcall(require, "codecompanion.providers.diff." .. provider)

          if ok and winnr then
            ---@type CodeCompanion.DiffArgs
            local diff_args = {
              bufnr = run_args.buffer,
              contents = api.nvim_buf_get_lines(run_args.buffer, 0, -1, true),
              filetype = api.nvim_buf_get_option(run_args.buffer, "filetype"),
              winnr = winnr,
            }
            ---@type CodeCompanion.Diff
            diff = diff.new(diff_args)
            keymaps
              .new({
                bufnr = run_args.buffer,
                callbacks = require("codecompanion.strategies.inline.keymaps"),
                data = { diff = diff },
                keymaps = config.strategies.inline.keymaps,
              })
              :set()

            diff_started = true
          end
        end

        if run_args.action == "add" then
          add(run_args)
        elseif run_args.action == "delete" then
          delete(run_args)
        elseif run_args.action == "update" then
          delete(run_args)
          add(run_args)
        end

        --TODO: Scroll to buffer and the new lines

        -- Automatically save the buffer
        if vim.g.codecompanion_auto_tool_mode then
          log:info("[Editor Tool] Auto-saving buffer")
          api.nvim_buf_call(run_args.buffer, function()
            vim.cmd("silent write")
          end)
        end

        return { status = "success", data = nil }
      end

      args.buffer = tonumber(args.buffer)
      if not args.buffer then
        return { status = "error", data = "No buffer number or buffer number conversion failed" }
      end

      local is_valid, _ = pcall(api.nvim_buf_is_valid, args.buffer)
      if not is_valid then
        return { status = "error", data = "Invalid buffer number" }
      end

      return run(args)
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "editor",
      description = "Add/edit/delete contents of a buffer in the user's Neovim instance",
      parameters = {
        type = "object",
        properties = {
          action = {
            type = "string",
            enum = { "add", "update", "delete" },
            description = "Action to perform: 'add', 'update', or 'delete'.",
          },
          buffer = {
            type = "integer",
            description = "Neovim buffer number",
          },
          code = {
            anyOf = {
              { type = "string" },
              { type = "null" },
            },
            description = "String of code to add/update; set to `null` when deleting.",
          },
          start_line = {
            type = "integer",
            description = "1‑based start line where the action begins.",
          },
          end_line = {
            anyOf = {
              { type = "integer" },
              { type = "null" },
            },
            description = "1‑based inclusive end line; set to `null` for add actions.",
          },
        },
        required = {
          "action",
          "buffer",
          "code",
          "start_line",
          "end_line",
        },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  system_prompt = string.format([[# Editor Tool (`editor`)

## CONTEXT
- You have access to an editor tool running within CodeCompanion, in Neovim.
- You can use it to add, edit or delete code in a Neovim buffer, via a buffer number that the user has provided to you.
- You can specify line numbers to add, edit or delete code and CodeCompanion will carry out the action in the buffer, on your behalf.

## OBJECTIVE
- To implement code changes in a Neovim buffer.

## RESPONSE
- Only invoke this tool when the user specifically asks.
- Use this tool strictly for code editing.
- If the user asks you to write specific code, do so to the letter, paying great attention.
- This tool can be called multiple times to make multiple changes to the same buffer.
- If the user has not provided you with a buffer number, you must ask them for one.
- Ensure that the code you write is syntactically correct and valid and that indentations are correct.

## POINTS TO NOTE
- This tool can be used alongside other tools within CodeCompanion
]]),
  handlers = {
    ---@param self CodeCompanion.Tool.Editor
    ---@param agent CodeCompanion.Agent
    on_exit = function(self, agent)
      deltas = {}
      diff_started = false
    end,
  },
  output = {
    ---@param self CodeCompanion.Tool.Editor
    ---@param agent CodeCompanion.Agent
    ---@param cmd table The command that was executed
    ---@param stdout table
    success = function(self, agent, cmd, stdout)
      local chat = agent.chat
      local args = self.args
      local buf = args.buffer

      if args.action == "delete" then
        local count = args.end_line - args.start_line + 1
        local short = fmt("**Editor Tool:** Deleted %d line(s) in buffer %d", count, buf)
        return chat:add_tool_output(self, short)
      end

      local lines = vim.split(args.code or "", "\n", { plain = true, trimempty = false })
      local count = #lines
      local verb = args.action == "add" and "Added" or "Updated"
      local short = fmt("**Editor Tool:** %s %d line(s) in buffer %d", verb, count, buf)
      local ft = vim.bo[buf].filetype
      local full = fmt("%s:\n```%s\n%s\n```", short, ft, table.concat(lines, "\n"))

      return chat:add_tool_output(self, full, short)
    end,
  },
}
