local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

local fmt = string.format

-- Terminal preview state management (global state for keymap access)
if not _G.codecompanion_terminal_preview then
  _G.codecompanion_terminal_preview = {
    bufnr = nil,
    winnr = nil,
    job_id = nil,
    is_active = false,
  }
end
local terminal_preview = _G.codecompanion_terminal_preview

---Create or show terminal preview window
---@param cmd string The command to run
---@return number bufnr, number winnr
local function create_terminal_preview(cmd)
  local title = fmt("Terminal Preview: %s", cmd)

  -- Create terminal buffer if it doesn't exist
  if not terminal_preview.bufnr or not vim.api.nvim_buf_is_valid(terminal_preview.bufnr) then
    terminal_preview.bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(terminal_preview.bufnr, title)

    -- Set buffer options
    vim.api.nvim_buf_set_option(terminal_preview.bufnr, "buftype", "nofile")
    vim.api.nvim_buf_set_option(terminal_preview.bufnr, "swapfile", false)
    vim.api.nvim_buf_set_option(terminal_preview.bufnr, "filetype", "terminal")
  end

  -- Create window if it doesn't exist or is not visible
  if not terminal_preview.winnr or not vim.api.nvim_win_is_valid(terminal_preview.winnr) then
    -- Create horizontal split at bottom
    vim.cmd("botright split")
    terminal_preview.winnr = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(terminal_preview.winnr, terminal_preview.bufnr)

    -- Set window size to 1/3 of screen height
    local total_height = vim.o.lines
    local preview_height = math.floor(total_height / 3)
    vim.api.nvim_win_set_height(terminal_preview.winnr, preview_height)

    -- Set window options
    vim.api.nvim_win_set_option(terminal_preview.winnr, "winfixheight", true)
    vim.wo[terminal_preview.winnr].number = false
    vim.wo[terminal_preview.winnr].relativenumber = false
    vim.wo[terminal_preview.winnr].signcolumn = "no"
  else
    -- Window exists, just focus it
    vim.api.nvim_set_current_win(terminal_preview.winnr)
  end

  return terminal_preview.bufnr, terminal_preview.winnr
end

---Run command in terminal preview
---@param cmd string|table The command to run
---@param callback? function Callback when command completes
local function run_command_in_preview(cmd, callback)
  local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
  local bufnr, winnr = create_terminal_preview(cmd_str)

  terminal_preview.is_active = true

  -- Clear buffer
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

  -- Add header
  local header = {
    fmt("=== Terminal Preview: %s ===", cmd_str),
    fmt("Started at: %s", os.date("%H:%M:%S")),
    "",
  }
  vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, header)

  -- Start terminal job
  terminal_preview.job_id = vim.fn.termopen(cmd_str, {
    cwd = vim.fn.getcwd(),
    on_stdout = function(_, data, _)
      if data then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(bufnr) then
            -- Scroll to bottom
            local line_count = vim.api.nvim_buf_line_count(bufnr)
            if winnr and vim.api.nvim_win_is_valid(winnr) then
              vim.api.nvim_win_set_cursor(winnr, { line_count, 0 })
            end
          end
        end)
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(bufnr) then
            -- Scroll to bottom
            local line_count = vim.api.nvim_buf_line_count(bufnr)
            if winnr and vim.api.nvim_win_is_valid(winnr) then
              vim.api.nvim_win_set_cursor(winnr, { line_count, 0 })
            end
          end
        end)
      end
    end,
    on_exit = function(job_id, exit_code, event_type)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          -- Add completion footer
          local footer = {
            "",
            fmt("=== Command completed with exit code: %d ===", exit_code),
            fmt("Finished at: %s", os.date("%H:%M:%S")),
          }
          vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, footer)

          -- Scroll to bottom
          if winnr and vim.api.nvim_win_is_valid(winnr) then
            local line_count = vim.api.nvim_buf_line_count(bufnr)
            vim.api.nvim_win_set_cursor(winnr, { line_count, 0 })
          end
        end

        terminal_preview.job_id = nil

        if callback then
          callback(exit_code)
        end

        log:debug("[cmd_runner] Terminal preview command completed with exit code: %d", exit_code)
      end)
    end,
  })

  -- Focus back to original window after starting
  vim.cmd("wincmd p")

  return terminal_preview.job_id
end

---@class CodeCompanion.Tool.CmdRunner: CodeCompanion.Tools.Tool
return {
  name = "cmd_runner",
  cmds = {
    -- This is dynamically populated via the setup function
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "cmd_runner",
      description = "Run shell commands on the user's system, sharing the output with the user before then sharing with you.",
      parameters = {
        type = "object",
        properties = {
          cmd = {
            type = "string",
            description = "The command to run, e.g. `pytest` or `make test`",
          },
          flag = {
            anyOf = {
              { type = "string" },
              { type = "null" },
            },
            description = 'If running tests, set to `"testing"`; null otherwise',
          },
          terminal_preview = {
            type = "boolean",
            description = "Whether to show command output in a live terminal preview window (default: false)",
          },
        },
        required = {
          "cmd",
          "flag",
        },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  system_prompt = fmt(
    [[# Command Runner Tool (`cmd_runner`)

## CONTEXT
- You have access to a command runner tool running within CodeCompanion, in Neovim.
- You can use it to run shell commands on the user's system.
- You may be asked to run a specific command or to determine the appropriate command to fulfil the user's request.
- All tool executions take place in the current working directory %s.
- You can optionally show command output in a live terminal preview window using the `terminal_preview` parameter.

## OBJECTIVE
- Follow the tool's schema.
- Respond with a single command, per tool execution.

## RESPONSE
- Only invoke this tool when the user specifically asks.
- If the user asks you to run a specific command, do so to the letter, paying great attention.
- Use this tool strictly for command execution; but file operations must NOT be executed in this tool unless the user explicitly approves.
- To run multiple commands, you will need to call this tool multiple times.

## SAFETY RESTRICTIONS
- Never execute the following dangerous commands under any circumstances:
  - `rm -rf /` or any variant targeting root directories
  - `rm -rf ~` or any command that could wipe out home directories
  - `rm -rf .` without specific context and explicit user confirmation
  - Any command with `:(){:|:&};:` or similar fork bombs
  - Any command that would expose sensitive information (keys, tokens, passwords)
  - Commands that intentionally create infinite loops
- For any destructive operation (delete, overwrite, etc.), always:
  1. Warn the user about potential consequences
  2. Request explicit confirmation before execution
  3. Suggest safer alternatives when available
- If unsure about a command's safety, decline to run it and explain your concerns

## POINTS TO NOTE
- This tool can be used alongside other tools within CodeCompanion

## USER ENVIRONMENT
- Shell: %s
- Operating System: %s
- Neovim Version: %s]],
    vim.fn.getcwd(),
    vim.o.shell,
    util.os(),
    vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch
  ),
  handlers = {
    ---@param self CodeCompanion.Tool.CmdRunner
    ---@param tool CodeCompanion.Tools The tool object
    setup = function(self, tool)
      local args = self.args

      -- Store terminal_preview preference for later use
      self._terminal_preview = args.terminal_preview or false

      -- If terminal preview is requested, use terminal preview mode
      if self._terminal_preview then
        -- Create a custom function-based command for terminal preview
        table.insert(self.cmds, function(agent, _, _, cb)
          cb = vim.schedule_wrap(cb)
          local job_id = run_command_in_preview(args.cmd, function(exit_code)
            -- Simulate vim.system output format for compatibility
            local success = exit_code == 0
            if success then
              -- Get output from terminal buffer
              local output = {}
              if terminal_preview.bufnr and vim.api.nvim_buf_is_valid(terminal_preview.bufnr) then
                local lines = vim.api.nvim_buf_get_lines(terminal_preview.bufnr, 0, -1, false)
                -- Filter out header/footer lines and get actual command output
                local start_idx, end_idx = 1, #lines
                for i, line in ipairs(lines) do
                  if line:match("^=== Terminal Preview:") then
                    start_idx = i + 3 -- Skip header lines
                  elseif line:match("^=== Command completed") then
                    end_idx = i - 2 -- Stop before footer
                    break
                  end
                end
                for i = start_idx, end_idx do
                  if lines[i] then
                    table.insert(output, lines[i])
                  end
                end
              end

              cb({
                status = "success",
                data = output,
              })
            else
              cb({
                status = "error",
                data = { fmt("Command failed with exit code: %d", exit_code) },
              })
            end
          end)

          -- Store job_id for potential cleanup
          if agent.chat then
            agent.chat.terminal_job = job_id
          end
        end)
      else
        -- Standard command setup for normal execution
        local cmd = { cmd = vim.split(args.cmd, " ") }
        if args.flag then
          cmd.flag = args.flag
        end
        table.insert(self.cmds, cmd)
      end
    end,
  },

  output = {
    ---Prompt the user to approve the execution of the command
    ---@param self CodeCompanion.Tool.CmdRunner
    ---@param tool CodeCompanion.Tools
    ---@return string
    prompt = function(self, tool)
      return fmt("Run the command `%s`?", self.args.cmd)
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tool.CmdRunner
    ---@param agent CodeCompanion.Tools
    ---@param cmd table
    ---@param feedback? string
    ---@return nil
    rejected = function(self, agent, cmd, feedback)
      local message = fmt("The user rejected the execution of the command `%s`", self.args.cmd)
      if feedback and feedback ~= "" then
        message = message .. fmt(" with feedback: %s", feedback)
      end
      agent.chat:add_tool_output(self, message)
    end,

    ---@param self CodeCompanion.Tool.CmdRunner
    ---@param tool CodeCompanion.Tools
    ---@param cmd table
    ---@param stderr table The error output from the command
    error = function(self, tool, cmd, stderr)
      local chat = tool.chat
      local errors = vim.iter(stderr):flatten():join("\n")

      local output = [[%s
```txt
%s
```]]

      local llm_output = fmt(output, fmt("There was an error running the `%s` command:", cmd.cmd), errors)
      local user_output = fmt(output, fmt("`%s` error", cmd.cmd), errors)

      chat:add_tool_output(self, llm_output, user_output)
    end,

    ---@param self CodeCompanion.Tool.CmdRunner
    ---@param tool CodeCompanion.Tools
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, tool, cmd, stdout)
      local chat = tool.chat
      if stdout and vim.tbl_isempty(stdout) then
        local message = "There was no output from the cmd_runner tool"
        if self._terminal_preview then
          message = message .. " (executed in terminal preview)"
        end
        return chat:add_tool_output(self, message)
      end
      local output = vim.iter(stdout[#stdout]):flatten():join("\n")
      local preview_note = self._terminal_preview and " (with terminal preview)" or ""
      local message = fmt(
        [[`%s`%s
```
%s
```]],
        self.args.cmd,
        preview_note,
        output
      )
      chat:add_tool_output(self, message)
    end,
  },
}
