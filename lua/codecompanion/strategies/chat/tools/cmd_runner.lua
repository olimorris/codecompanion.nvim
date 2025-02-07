--[[
*Command Runner Tool*
This tool is used to run shell commands on your system. It can handle multiple
commands in the same XML block. All commands must be approved by you.
--]]

local config = require("codecompanion.config")

local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

---@class CmdRunner.ChatOpts
---@field cmd table|string The command that was executed
---@field output table|string The output of the command
---@field message? string An optional message

---Outputs a message to the chat buffer that initiated the tool
---@param msg string The message to output
---@param tool CodeCompanion.Tools The tools object
---@param opts CmdRunner.ChatOpts
local function to_chat(msg, tool, opts)
  if type(opts.cmd) == "table" then
    opts.cmd = table.concat(opts.cmd, " ")
  end
  if type(opts.output) == "table" then
    opts.output = table.concat(opts.output, "\n")
  end

  local content
  if opts.output == "" then
    content = string.format(
      [[%s the command `%s`.

]],
      msg,
      opts.cmd
    )
  else
    content = string.format(
      [[%s the command `%s`:

```txt
%s
```

]],
      msg,
      opts.cmd,
      opts.output
    )
  end

  return tool.chat:add_buf_message({
    role = config.constants.USER_ROLE,
    content = content,
  })
end

---@class CodeCompanion.Tool
return {
  name = "cmd_runner",
  cmds = {
    -- Dynamically populate this table via the setup function
  },
  schema = {
    {
      tool = {
        _attr = { name = "cmd_runner" },
        action = {
          command = "<![CDATA[gem install rspec]]>",
        },
      },
    },
    {
      tool = { name = "cmd_runner" },
      action = {
        {
          command = "<![CDATA[gem install rspec]]>",
        },
        {
          command = "<![CDATA[gem install rubocop]]>",
        },
      },
    },
    {
      tool = {
        _attr = { name = "cmd_runner" },
        action = {
          flag = "testing",
          command = "<![CDATA[make test]]>",
        },
      },
    },
  },
  system_prompt = function(schema)
    return string.format(
      [[## Command Runner Tool (`cmd_runner`) – Enhanced Guidelines

### Purpose:
- Execute safe, validated shell commands on the user's system when explicitly requested.

### When to Use:
- Only invoke the command runner when the user specifically asks.
- Use this tool strictly for command execution; file operations must be handled with the designated Files Tool.

### Execution Format:
- Always return an XML markdown code block.
- Each shell command execution should:
  - Be wrapped in a CDATA section to protect special characters.
  - Follow the XML schema exactly.
- If several commands need to run sequentially, combine them in one XML block with separate <action> entries.

### XML Schema:
- The XML must be valid. Each tool invocation should adhere to this structure:

```xml
%s
```

- Combine multiple shell commands in one response if needed and they will be executed sequentially:

```xml
%s
```

- If the user asks you to run tests or a test suite, be sure to include a testing flag so the Neovim editor is aware:

```xml
%s
```

### Key Considerations
- **Safety First:** Ensure every command is safe and validated.
- **User Environment Awareness:**
  - **Shell**: %s
  - **Operating System**: %s
  - **Neovim Version**: %s
- **User Oversight:** The user retains full control with an approval mechanism before execution.
- **Extensibility:** If environment details aren’t available (e.g., language version details), output the command first along with a request for more information.

### Reminder
- Minimize explanations and focus on returning precise XML blocks with CDATA-wrapped commands.
- Follow this structure each time to ensure consistency and reliability.]],
      xml2lua.toXml({ tools = { schema[1] } }), -- Regular
      xml2lua.toXml({ -- Multiple
        tools = {
          tool = {
            _attr = { name = "cmd_runner" },
            action = {
              schema[2].action[1],
              schema[2].action[2],
            },
          },
        },
      }),
      xml2lua.toXml({ tools = { schema[3] } }), -- Testing flag
      vim.o.shell,
      util.os(),
      vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch
    )
  end,
  handlers = {
    ---@param self CodeCompanion.Tools The tool object
    setup = function(self)
      local tool = self.tool --[[@type CodeCompanion.Tool]]
      local action = tool.request.action
      local actions = vim.isarray(action) and action or { action }

      for _, act in ipairs(actions) do
        local entry = { cmd = vim.split(act.command, " ") }
        if act.flag then
          entry.flag = act.flag
        end
        table.insert(tool.cmds, entry)
      end
    end,

    ---Approve the command to be run
    ---@param self CodeCompanion.Tools The tool object
    ---@param cmd table
    ---@return boolean
    approved = function(self, cmd)
      if vim.g.codecompanion_auto_tool_mode then
        log:info("[Cmd Runner Tool] Auto-approved running the command")
        return true
      end

      local cmd_concat = table.concat(cmd.cmd or cmd, " ")

      local msg = "Run command: `" .. cmd_concat .. "`?"
      local ok, choice = pcall(vim.fn.confirm, msg, "No\nYes")
      if not ok or choice ~= 2 then
        log:info("[Cmd Runner Tool] Rejected running the command")
        return false
      end

      log:info("[Cmd Runner Tool] Approved running the command")
      return true
    end,
  },

  output = {
    ---Rejection message back to the LLM
    rejected = function(self, cmd)
      to_chat("I chose not to run", self, { cmd = cmd.cmd or cmd, output = "" })
    end,

    ---@param self CodeCompanion.Tools The tools object
    ---@param cmd table|string The command that was executed
    ---@param stderr table|string
    error = function(self, cmd, stderr)
      to_chat("There was an error from", self, { cmd = cmd.cmd or cmd, output = stderr })
    end,

    ---@param self CodeCompanion.Tools The tools object
    ---@param cmd table|string The command that was executed
    ---@param stdout table|string
    success = function(self, cmd, stdout)
      to_chat("The output from", self, { cmd = cmd.cmd or cmd, output = stdout })
    end,
  },
}
