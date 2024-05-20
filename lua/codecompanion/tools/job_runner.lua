local Job = require("plenary.job")

local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local M = {}

local stderr = {}
local stdout = {}
local status = ""

local api = vim.api

local function on_start()
  api.nvim_exec_autocmds("User", { pattern = "CodeCompanionTool", data = { status = "started" } })
end
local function on_finish()
  api.nvim_exec_autocmds(
    "User",
    { pattern = "CodeCompanionTool", data = { status = status, error = stderr, output = stdout } }
  )
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
    on_exit = function(_, exit_code)
      run_jobs(cmds, index + 1)

      vim.schedule(function()
        if index == #cmds then
          if exit_code ~= 0 then
            status = "error"
            log:error("Job failed with exit code: %d", exit_code)
          end
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
      table.insert(stderr, data)
    end,
  }):start()
end

function M.run(cmds)
  -- Reset defaults
  status = "success"
  stderr = {}
  stdout = {}

  on_start()
  return run_jobs(cmds, 1)
end

return M
