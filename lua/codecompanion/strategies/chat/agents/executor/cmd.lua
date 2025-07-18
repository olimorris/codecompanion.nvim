local Job = require("plenary.job")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.Agent.Executor.Cmd
---@field executor CodeCompanion.Agent.Executor
---@field cmds table
---@field count number
---@field index number
local CmdExecutor = {}

---@param executor CodeCompanion.Agent.Executor
---@param cmds table
---@param index number
function CmdExecutor.new(executor, cmds, index)
  return setmetatable({
    executor = executor,
    cmds = cmds,
    count = vim.tbl_count(cmds),
    index = index,
  }, { __index = CmdExecutor })
end

---Orchestrate the tool function
---@return nil
function CmdExecutor:orchestrate()
  log:debug("CmdExecutor:orchestrate %s", self.cmds)

  for i = self.index, self.count do
    self:run(self.cmds[i], i)
  end
end

---Some commands output ANSI color codes which don't render in the chat buffer
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
---@param index number
---@return nil
function CmdExecutor:run(cmd, index)
  log:debug("CmdExecutor:run %s", cmd)

  local job = Job:new({
    command = (vim.fn.has("win32") == 1 and "cmd.exe" or "sh"),
    args = { vim.fn.has("win32") == 1 and "/c" or "-c", table.concat(cmd.cmd or cmd, " ") },
    enable_recording = true,
    cwd = vim.fn.getcwd(),
    on_exit = function(data, code)
      log:debug("CmdExecutor:run - on_exit")
      self.executor.current_cmd_tool = nil

      -- Flags can be inserted into the chat buffer to be picked up later
      if cmd.flag then
        self.executor.agent.chat.tools.flags = self.executor.agent.chat.tools.flags or {}
        self.executor.agent.chat.tools.flags[cmd.flag] = (code == 0)
      end

      vim.schedule(function()
        local ok, output = pcall(function()
          if _G.codecompanion_cancel_tool then
            return self.executor:close()
          end

          if data and data._stderr_results then
            self.executor.agent.stderr = {}
            table.insert(self.executor.agent.stderr, strip_ansi(data._stderr_results))
          end
          if data and data._stdout_results then
            self.executor.agent.stdout = {}
            table.insert(self.executor.agent.stdout, strip_ansi(data._stdout_results))
          end
          if code == 0 then
            self.executor:success(cmd)
            -- Don't trigger the on_exit handler unless it's the last command
            if index == self.count then
              self.executor:close()
              return self.executor:setup()
            end
          else
            self.executor:error(cmd, string.format("Failed with code %s", code))
            return self.executor:close()
          end
        end)

        if not ok then
          self.executor:error(cmd, string.format("Error whilst running command %s: %s", cmd, output))
          return self.executor:close()
        end
      end)
    end,
  })

  if not vim.tbl_isempty(self.executor.current_cmd_tool) then
    self.executor.current_cmd_tool:and_then_wrap(job)
  else
    job:start()
  end

  self.executor.current_cmd_tool = job
end

return CmdExecutor
