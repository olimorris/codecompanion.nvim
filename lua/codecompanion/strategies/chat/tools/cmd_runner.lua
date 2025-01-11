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
          command = "<![CDATA[rspec]]>",
        },
      },
    },
  },
  system_prompt = function(schema)
    return string.format(
      [[### Command Runner Tool

1. **Purpose**: Run commands in a user's shell.

2. **Usage**: Return an XML markdown code block with a shell command to be executed. The command should be valid and safe to run on the user's system.

3. **Key Points**:
  - **Only use when you deem it necessary**. The user has the final control on these operations through an approval mechanism
  - Ensure XML is **valid and follows the schema**
  - **Don't escape** special characters
  - **Wrap the command in a CDATA block**, the command could contain characters reserved by XML
  - If you need information which hasn't been provided to you (e.g. the version of a language you've been asked to write a command in), write that command first and inform the user
  - The output from each command will be shared with you after each command executes
  - Don't use this action to run file commands, use the Files Tool instead. If you don't have access to that then consider whether file operations are required
  - Make sure the tools xml block is **surrounded by ```xml**

4. **Actions**:

```xml
%s
```

5. **Multiple Commands**: Combine multiple shell commands in one response if needed:

```xml
%s
```

They will be executed sequentially.

6. **The User's Environment**: Information that you may need when running commands:
  - **Shell**: %s
  - **Operating System**: %s
  - **Neovim Version**: %s

Remember:
- Minimize explanations unless prompted. Focus on generating correct XML and good commands.]],
      xml2lua.toXml({ tools = { schema[1] } }),
      xml2lua.toXml({
        tools = {
          tool = {
            _attr = { name = "cmd_runner" },
            action = {
              schema[#schema].action[1],
              schema[#schema].action[2],
            },
          },
        },
      }),
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
      if util.is_array(action) then
        for _, v in ipairs(action) do
          local split = vim.split(v.command, " ")
          table.insert(tool.cmds, split)
        end
      else
        local split = vim.split(action.command, " ")
        table.insert(tool.cmds, split)
      end
    end,

    ---Approve the command to be run
    ---@param self CodeCompanion.Tools The tool object
    ---@param cmd table
    ---@return boolean
    approved = function(self, cmd)
      local cmd_concat = table.concat(cmd, " ")

      local msg = "Run command: " .. cmd_concat .. " ?"
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
      to_chat("I chose not to run", self, { cmd = cmd, output = "" })
    end,

    ---@param self CodeCompanion.Tools The tools object
    ---@param cmd table|string The command that was executed
    ---@param stderr table|string
    error = function(self, cmd, stderr)
      to_chat("There was an error from", self, { cmd = cmd, output = stderr })
    end,

    ---@param self CodeCompanion.Tools The tools object
    ---@param cmd table|string The command that was executed
    ---@param stdout table|string
    success = function(self, cmd, stdout)
      to_chat("The output from", self, { cmd = cmd, output = stdout })
    end,
  },
}
