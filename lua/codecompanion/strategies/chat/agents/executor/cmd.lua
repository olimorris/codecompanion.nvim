local Job = require("plenary.job")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.Agent.Executor.Cmd
---@field executor CodeCompanion.Agent.Executor
---@field cmd table
---@field index number
local CmdExecutor = {}

---@param executor CodeCompanion.Agent.Executor
---@param cmd table
---@param index number
function CmdExecutor.new(executor, cmd, index)
  return setmetatable({
    executor = executor,
    cmd = cmd,
    index = index,
  }, { __index = CmdExecutor })
end

---Orchestrate the tool function
---@return nil
function CmdExecutor:orchestrate()
  log:debug("CmdExecutor:orchestrate %s", self.cmd)
  self:run(self.cmd)
end

---Some commands output ANSI color codes so we need to strip them
---@param tbl table
---@return table
local function strip_ansi(tbl)
  for i, v in ipairs(tbl) do
    tbl[i] = v:gsub("\027%[[0-9;]*%a", "")
  end
  return tbl
end

---Run the tool's function
---@param cmd table
---@return nil
function CmdExecutor:run(cmd)
  log:debug("CmdExecutor:run %s", cmd)

  local job = Job:new({
    command = vim.fn.has("win32") == 1 and "cmd.exe" or "sh",
    args = { vim.fn.has("win32") == 1 and "/c" or "-c", table.concat(cmd.cmd or cmd, " ") },
    enable_recording = true,
    cwd = vim.fn.getcwd(),
    on_exit = function(data, code)
      log:debug("CmdExecutor:run - on_exit")

      self.executor.current_cmd_tool = nil

      -- Flags can be inserted into the chat buffer to be picked up later
      if cmd.flag then
        self.executor.agent.chat.tool_flags = self.executor.agent.chat.tool_flags or {}
        self.executor.agent.chat.tool_flags[cmd.flag] = (code == 0)
      end

      vim.schedule(function()
        local ok, _ = pcall(function()
          if _G.codecompanion_cancel_tool then
            return self.executor:close()
          end
          if data then
            if data._stderr_results then
              table.insert(self.executor.agent.stderr, strip_ansi(data._stderr_results))
            end
            if data._stdout_results then
              table.insert(self.executor.agent.stdout, strip_ansi(data._stdout_results))
            end
          end
          if code == 0 then
            self.executor:success(cmd)
            return self.executor:close()
          else
            return self.executor:error(cmd, string.format("Command failed with code %s", code))
          end
        end)

        if not ok then
          log:error("Internal error running command: %s", cmd)
        end
      end)
    end,
  })

  if not vim.tbl_isempty(self.executor.current_cmd_tool) then
    self.executor.current_cmd_tool:and_then(job)
  else
    job:start()
  end

  self.executor.current_cmd_tool = job
end

return CmdExecutor
