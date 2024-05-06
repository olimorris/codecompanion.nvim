local config = require("codecompanion.config")
local job = require("plenary.job")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils.util")

local m = {}

local function on_finished(data, bufnr)
  return vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionToolFinished", data = { output = data } })
end

local function run_jobs(cmds, index, bufnr)
  if index > #cmds then
    return
  end

  local cmd = cmds[index]

  log:debug("running cmd: %s", cmd)

  job
    :new({
      command = cmd[1],
      args = { unpack(cmd, 2) }, -- args start from index 2
      on_exit = function(_, _)
        run_jobs(cmds, index + 1, opts)
      end,
      on_stdout = function(_, data)
        vim.schedule(function()
          log:debug("stdout: %s", data)
          if index == #cmds then
            return on_finished(data, bufnr)
          end
        end)
      end,
      on_stderr = function(_, data)
        vim.schedule(function()
          log:error("Error running job: %s", data)
        end)
      end,
    })
    :start()
end

function m.run(bufnr, tool)
  log:info("code runner initiated")

  -- set the variables that the user can use in their environment
  local temp_input = vim.fn.tempname()
  local temp_dir = temp_input:match("(.*/)")
  local temp_output = vim.fn.tempname()
  local lang = tool.parameters.inputs.lang
  local code = tool.parameters.inputs.code

  -- and apply them to the tool commands
  local cmds = config.options.tools.code_runner.cmds
  utils.replace_placeholders(cmds, {
    code = code,
    lang = lang,
    temp_dir = temp_dir,
    temp_input = temp_input,
    temp_output = temp_output,
  })

  -- write the code to a temporary file
  local file = io.open(temp_input, "w")
  if file then
    file:write(code)
    file:close()
  else
    log:error("failed to write code to temporary file")
    return
  end

  run_jobs(cmds, 1, bufnr)
end

return m
