local Job = require("plenary.job")

local log = require("codecompanion.utils.log")

local M = {}

local stderr = {}
local stdout = {}
local status = ""

local api = vim.api

---@param bufnr number
local function announce_start(bufnr)
  api.nvim_exec_autocmds("User", { pattern = "CodeCompanionTool", data = { bufnr = bufnr, status = "started" } })
end

---@param bufnr number
local function announce_end(bufnr)
  api.nvim_exec_autocmds(
    "User",
    { pattern = "CodeCompanionTool", data = { bufnr = bufnr, status = status, error = stderr, output = stdout } }
  )
end

---Run the jobs
---@param cmds table
---@param bufnr number
---@param index number
---@return nil
local function run(cmds, bufnr, index)
  if index > #cmds then
    return
  end

  local cmd = cmds[index]

  log:debug("Running cmd: %s", cmd)

  Job:new({
    command = cmd[1],
    args = { unpack(cmd, 2) }, -- args start from index 2
    on_exit = function(_, exit_code)
      run(cmds, bufnr, index + 1)

      vim.schedule(function()
        if index == #cmds then
          if exit_code ~= 0 then
            status = "error"
            log:error("Command failed: %s", stderr)
          end
          return announce_end(bufnr)
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

---Initiate the job runner
---@param cmds table
---@param bufnr number
---@return nil
function M.init(cmds, bufnr)
  -- Reset defaults
  status = "success"
  stderr = {}
  stdout = {}

  announce_start(bufnr)
  return run(cmds, bufnr, 1)
end

return M
