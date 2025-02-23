--[[
-- The purpose of this file is to abstract away any command logic from Plenary's
-- Job API. This makes it soooooo much easier to test as we decouple it from
-- the cmd executor file.
--]]

local log = require("codecompanion.utils.log")

---@class CodeCompanion.Agent.Executor.CmdHandlers
local CmdHandlers = {}

---Strip ANSI color codes from output
---@param tbl table
---@return table
local function strip_ansi(tbl)
  for i, v in ipairs(tbl) do
    tbl[i] = v:gsub("\027%[[0-9;]*%a", "")
  end
  return tbl
end

---The command to run
---@return string
function CmdHandlers.command()
  return vim.fn.has("win32") == 1 and "cmd.exe" or "sh"
end

---The command arguments
---@param cmd table
---@return table
function CmdHandlers.args(cmd)
  return { vim.fn.has("win32") == 1 and "/c" or "-c", table.concat(cmd.cmd or cmd, " ") }
end

---Handle job exit
---@param executor CodeCompanion.Agent.Executor.Cmd
---@param cmd table Command being executed
---@param data table Job data containing stdout/stderr results
---@param code number Exit code
function CmdHandlers.on_exit(executor, cmd, data, code)
  log:debug("CmdExecutor:run - on_exit")
  executor.executor.current_cmd_tool = nil

  -- Flags can be inserted into the chat buffer to be picked up later
  if cmd.flag then
    executor.executor.agent.chat.tool_flags = executor.executor.agent.chat.tool_flags or {}
    executor.executor.agent.chat.tool_flags[cmd.flag] = (code == 0)
  end

  vim.schedule(function()
    local ok, _ = pcall(function()
      if _G.codecompanion_cancel_tool then
        return executor.executor:close()
      end
      if data and data._stderr_results then
        table.insert(executor.executor.agent.stderr, strip_ansi(data._stderr_results))
      end
      if data and data._stdout_results then
        table.insert(executor.executor.agent.stdout, strip_ansi(data._stdout_results))
      end
      if code == 0 then
        executor.executor:success(cmd)
        return executor.executor:close()
      else
        return executor.executor:error(cmd, string.format("Failed with code %s", code))
      end
    end)

    if not ok then
      log:error("Internal error running command: %s", cmd)
    end
  end)
end

return CmdHandlers
