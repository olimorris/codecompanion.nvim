local Job = require("plenary.job")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils.util")

local api = vim.api

local M = {}

local stdout = {}
local status = ""

local function on_start()
  api.nvim_exec_autocmds("User", { pattern = "CodeCompanionTool", data = { status = "started" } })
end
local function on_finish()
  api.nvim_exec_autocmds("User", { pattern = "CodeCompanionTool", data = { status = status, output = stdout } })
end

---@param cmds table
---@param index number
---@return nil
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

---@param bufnr number
---@param tool table
---@return nil|table
function M.run(bufnr, tool)
  log:info("code runner initiated")

  -- Reset the status and stdout
  status = "success"
  stdout = {}

  -- set the variables that the user can use in their environment
  local temp_input = vim.fn.tempname()
  local temp_dir = temp_input:match("(.*/)")
  local lang = tool.parameters.inputs.lang
  local code = tool.parameters.inputs.code

  -- and apply them to the tool commands
  local cmds = vim.deepcopy(config.options.tools.code_runner.cmds.default)
  utils.replace_placeholders(cmds, {
    code = code,
    lang = lang,
    temp_dir = temp_dir,
    temp_input = temp_input,
  })

  -- Write the code to a temporary file
  local file = io.open(temp_input, "w")
  if file then
    file:write(code)
    file:close()
  else
    log:error("failed to write code to temporary file")
    return
  end

  on_start()
  return run_jobs(cmds, 1)
end

return M
