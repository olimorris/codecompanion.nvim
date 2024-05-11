local Job = require("plenary.job")
local log = require("codecompanion.utils.log")

local M = {}

local stdout = {}
local status = ""

local api = vim.api

local function on_start()
  api.nvim_exec_autocmds("User", { pattern = "CodeCompanionTool", data = { status = "started" } })
end
local function on_finish()
  api.nvim_exec_autocmds("User", { pattern = "CodeCompanionTool", data = { status = status, output = stdout } })
end

local function run_jobs(cmds, index)
  if index > #cmds then
    return
  end

  local cmd = cmds[index]

  log:debug("running cmd: %s", cmd)

  Job:new({
    command = cmd[1],
    args = { unpack(cmd, 2) }, -- args start from index 2
    on_exit = function(_, _)
      run_jobs(cmds, index + 1)

      vim.schedule(function()
        if index == #cmds then
          return on_finish()
        end
      end)
    end,
    on_stdout = function(_, data)
      vim.schedule(function()
        log:debug("stdout: %s", data)
        if index == #cmds then
          table.insert(stdout, data)
        end
      end)
    end,
    on_stderr = function(_, data)
      status = "error"
      vim.schedule(function()
        log:error("Error running job: %s", data)
      end)
    end,
  }):start()
end

function M.run(cmds)
  -- Reset the status and stdout
  status = "success"
  stdout = {}

  on_start()
  return run_jobs(cmds, 1)
end

return M
