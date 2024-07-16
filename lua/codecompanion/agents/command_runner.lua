local Job = require("plenary.job")
local config = require("codecompanion").config
local util = require("codecompanion.utils.agent")
local api = vim.api
local log = require("codecompanion.utils.log")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

---@type CodeCompanion.Agent
local M = {}

M.schema = {
  name = "command_runner",
  parameters = {
    inputs = {
      cmd = "The command to execute",
      -- args = {
      --   arg = "The arguments to pass to the command",
      -- },
      arg = "The arguments to pass to the command",
    },
  },
}

M.prompts = {
  {
    role = "system",
    content = function(schema)
      return "To aid you further, I'm giving you access to Command Runner which can run command in user's terminal."
        .. [[Please be very cautious when suggesting commands, as they will be executed on the user's system. If the command may have destructive effects, please inform the user as first.
]]
        .. "To use Command Runner, provide a command in the following format:\n\n"
        .. "```xml\n"
        .. xml2lua.toXml(schema, "agent")
        .. [[

```

Here's an example of how to use the Command Runner agent:

```xml
<agent>
  <name>command_runner</name>
  <parameters>
    <inputs>
      <cmd>ls</cmd>
      <arg>-l</arg>
      <arg>-a</arg>
    </inputs>
  </parameters>
</agent>
```

This example demonstrates how to list all files in the current directory, including hidden files, with detailed information. Always ensure the command is safe and appropriate for the user's needs. After executing a command, I will provide you with the output, which you should interpret and use to inform your next actions or responses.]]
    end,
  },
  {
    role = "user",
    content = function(context)
      return ""
    end,
  },
}

function M.execute(chat, params, last_execute)
  local cmd = params.cmd
  log:trace("command Runner: Executing command: %s", cmd)
  log:trace("command Runner: Executing command: %s", params.arg)
  if not cmd then
    log:error("command is required")
    util.announce_end(chat.bufnr, "error", { "Command is required" }, {}, last_execute)
    return
  end

  local status = "success"
  local stderr = {}

  local job = Job:new({
    command = params.cmd,
    args = type(params.arg) == "table" and params.arg or { type(params.arg) == "string" and params.arg or "" },
    on_start = function()
      log:trace("Command Runner: Starting command: %s", cmd)
      util.announce_progress(chat.bufnr, "progress", "Command executed successfully. output: \n ```\n")
    end,
    on_exit = function(j, exit_code)
      vim.schedule(function()
        log:trace("Command Runner: Command exited with code: %s", exit_code)
        util.announce_progress(chat.bufnr, "progress", "\n```\n")

        if _G.codecompanion_cancel_agent then
          return util.announce_end(chat.bufnr, status, stderr, nil, last_execute)
        end

        if exit_code ~= 0 then
          status = "error"
          log:info("Command failed: %s", stderr)
        end
        log:trace("Command Runner: Command output: %s", j:result())
        return util.announce_end(chat.bufnr, status, stderr, j:result(), last_execute)
      end)
    end,
    on_stdout = vim.schedule_wrap(function(_, data)
      if data then
        log:trace("command runner stdout: %s", data)
        util.announce_progress(chat.bufnr, "progress", data)
      end
    end),
    on_stderr = function(_, data)
      if data then
        log:trace("command runner stderr: %s", data)
        table.insert(stderr, data)
      end
    end,
  })

  chat.current_agent = job
  job:start()
end

M.output_error_prompt = function(error)
  return "After the command_runner completed, there was an error:"
    .. "\n```\n"
    .. table.concat(error, "\n")
    .. "\n```\n"
end

M.output_prompt = function(output)
  return "After the command_runner completed the output was:" .. "\n```\n" .. table.concat(output, "\n") .. "\n```\n"
end

return M
