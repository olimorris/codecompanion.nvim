local Job = require("plenary.job")
local handlers = require("codecompanion.strategies.chat.agents.executor.cmd_handlers")
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
    command = handlers.command(),
    args = handlers.args(cmd),
    enable_recording = true,
    cwd = vim.fn.getcwd(),
    on_exit = function(data, code)
      handlers.on_exit(self, cmd, data, code)
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
