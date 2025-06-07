local Path = require("plenary.path")
local buffers = require("codecompanion.utils.buffers")
local config = require("codecompanion.config")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local patch = require("codecompanion.strategies.chat.agents.tools.helpers.patch")
local ui = require("codecompanion.utils.ui")

local api = vim.api
local fmt = string.format

local PROMPT = [[<editFileInstructions>
Before editing a file, ensure you have its content via the provided context or read_file tool.
Use the insert_edit_into_file tool to modify files.
NEVER show the code edits to the user - only call the tool. The system will apply and display the changes.
For each file, give a short description of what needs to be changed, then use the insert_edit_into_file tools. You can use the tool multiple times in a response, and you can keep writing text after using a tool.
The insert_edit_into_file tool is very smart and can understand how to apply your edits to the user's files, you just need to follow the patch format instructions carefully and to the letter.

## Patch Format
]] .. patch.FORMAT_PROMPT .. [[
The system uses fuzzy matching and confidence scoring so focus on providing enough context to uniquely identify the location.
</editFileInstructions>]]

---Edit code in a file
---@param action {filepath: string, code: string, explanation: string} The arguments from the LLM's tool call
---@return string
local function edit_file(action)
  local filepath = vim.fs.joinpath(vim.fn.getcwd(), action.filepath)
  local p = Path:new(filepath)
  p.filename = p:expand()

  -- 1. extract list of changes from the code
  local raw = action.code or ""
  local changes = patch.parse_changes(raw)

  -- 2. read file into lines
  local content = p:read()
  local lines = vim.split(content, "\n", { plain = true })

  -- 3. apply changes
  for _, change in ipairs(changes) do
    local new_lines = patch.apply_change(lines, change)
    if new_lines == nil then
      error(fmt("Bad/Incorrect diff:\n\n%s\n\nNo changes were applied", patch.get_change_string(change)))
    else
      lines = new_lines
    end
  end

  -- 4. write back
  p:write(table.concat(lines, "\n"), "w")

  -- 5. refresh the buffer if the file is open
  local bufnr = vim.fn.bufnr(p.filename)
  if bufnr ~= -1 and api.nvim_buf_is_loaded(bufnr) then
    api.nvim_command("checktime " .. bufnr)
  end
  return fmt("**Insert Edit Into File Tool**: `%s` - %s", action.filepath, action.explanation)
end

---Edit code in a buffer
---@param action {filepath: string, code: string, explanation: string} The arguments from the LLM's tool call
---@return string
local function edit_buffer(bufnr, action)
  -- Initialize diff if enabled and not in auto mode
  if not vim.g.codecompanion_auto_tool_mode and config.display.diff.enabled and vim.bo[bufnr].buftype ~= "terminal" then
    local provider = config.display.diff.provider
    local ok, diff = pcall(require, "codecompanion.providers.diff." .. provider)
    local winnr = ui.buf_get_win(bufnr)

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
    end
  end

  -- Parse and apply patches to buffer
  local raw = action.code or ""
  local changes = patch.parse_changes(raw)

  -- Get current buffer content as lines
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Apply each change
  for _, change in ipairs(changes) do
    local new_lines = patch.apply_change(lines, change)
    if new_lines == nil then
      error(fmt("Bad/Incorrect diff:\n\n%s\n\nNo changes were applied", patch.get_change_string(change)))
    else
      lines = new_lines
    end
  end

  -- Update the buffer with new content
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Auto-save if enabled
  if vim.g.codecompanion_auto_tool_mode then
    log:info("[Insert Edit Into File Tool] Auto-saving buffer")
    api.nvim_buf_call(bufnr, function()
      vim.cmd("silent write")
    end)
  end

  return fmt("**Insert Edit Into File Tool**: `%s` - %s", action.filepath, action.explanation)
end

---Edit code
---@param action {filepath: string, code: string, explanation: string} The arguments from the LLM's tool call
---@return string
local function edit(action)
  local bufnr = buffers.get_bufnr_from_filepath(action.filepath)
  if bufnr then
    return edit_buffer(bufnr, action)
  end
  return edit_file(action)
end

---@class CodeCompanion.Tool.InsertEditIntoFile: CodeCompanion.Agent.Tool
return {
  name = "insert_edit_into_file",
  cmds = {
    ---Execute the file commands
    ---@param self CodeCompanion.Tool.Editor The Editor tool
    ---@param args table The arguments from the LLM's tool call
    ---@param input? any The output from the previous function call
    ---@return { status: "success"|"error", data: string }
    function(self, args, input)
      local ok, outcome = pcall(edit, args)
      if not ok then
        return { status = "error", data = outcome }
      end
      return { status = "success", data = outcome }
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "insert_edit_into_file",
      description = "Insert new code or modify existing code in a file in the current working directory. Use this tool once per file that needs to be modified, even if there are multiple changes for a file. The system is very smart and can understand how to apply your edits to the user's files if you follow the instructions.",
      parameters = {
        type = "object",
        properties = {
          explanation = {
            type = "string",
            description = "A short explanation of the code edit being made",
          },
          filepath = {
            type = "string",
            description = "The relative path to the file to edit, including its filename and extension",
          },
          code = {
            type = "string",
            description = "The code which follows the patch format",
          },
        },
        required = {
          "explanation",
          "filepath",
          "code",
        },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  system_prompt = PROMPT,
  handlers = {
    ---@param agent CodeCompanion.Agent The tool object
    ---@return nil
    on_exit = function(agent)
      log:trace("[Insert Edit Into File Tool] on_exit handler executed")
    end,
  },
  output = {
    ---The message which is shared with the user when asking for their approval
    ---@param self CodeCompanion.Agent.Tool
    ---@param agent CodeCompanion.Agent
    ---@return nil|string
    prompt = function(self, agent)
      local args = self.args
      local filepath = vim.fn.fnamemodify(args.filepath, ":.")
      return fmt("Edit the file at %s?", filepath)
    end,

    ---@param self CodeCompanion.Tool.InsertEditIntoFile
    ---@param agent CodeCompanion.Agent
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, agent, cmd, stdout)
      local llm_output = vim.iter(stdout):flatten():join("\n")
      agent.chat:add_tool_output(self, llm_output)
    end,

    ---@param self CodeCompanion.Tool.InsertEditIntoFile
    ---@param agent CodeCompanion.Agent
    ---@param cmd table
    ---@param stderr table The error output from the command
    ---@param stdout? table The output from the command
    error = function(self, agent, cmd, stderr, stdout)
      local chat = agent.chat
      local args = self.args
      local errors = vim.iter(stderr):flatten():join("\n")
      log:debug("[Insert Edit Into File Tool] Error output: %s", stderr)

      local error_output = fmt(
        [[**Insert Edit Into File Tool**: Ran with an error:

```txt
%s
```]],
        errors
      )
      chat:add_tool_output(self, error_output)
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tool.InsertEditIntoFile
    ---@param agent CodeCompanion.Agent
    ---@param cmd table
    ---@return nil
    rejected = function(self, agent, cmd)
      local chat = agent.chat
      chat:add_tool_output(self, "**Insert Edit Into File Tool**: The user declined to execute")
    end,
  },
}
