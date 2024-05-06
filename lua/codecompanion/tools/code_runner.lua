local Job = require("plenary.job")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils.util")

local M = {}

function M.run(bufnr, tool)
  log:info("Code Runner initiated")

  -- Set the variables that the user can use in their environment
  local temp_input = vim.fn.tempname()
  local temp_dir = temp_input:match("(.*/)")
  local temp_output = vim.fn.tempname()
  local lang = tool.parameters.inputs.lang
  local code = tool.parameters.inputs.code

  local cmds = config.options.tools.code_runner.env.cmd
  utils.replace_placeholders(cmds, {
    code = code,
    lang = lang,
    temp_dir = temp_dir,
    temp_input = temp_input,
    temp_output = temp_output,
  })

  -- Write the code to a temporary file
  local file = io.open(temp_input, "w")
  if file then
    file:write(code)
    file:close()
  else
    log:error("Failed to write code to temporary file")
    return
  end

  -- Run the code
  local errors = {}
  for _, cmd in ipairs(cmds) do
    local args = {}
    for arg in cmd:gmatch("%S+") do
      table.insert(args, arg)
    end

    log:debug('Running command: "%s"', cmd)

    Job:new({
      command = args[1],
      args = { unpack(args, 2) }, -- args start from 2
      on_stderr = function(_, data)
        table.insert(errors, 'Failed to run command: "' .. cmd .. '"')
        table.insert(errors, 'Error output: "' .. data .. '"')
      end,
    }):start()
  end

  if errors and #errors > 0 then
    for _, error in ipairs(errors) do
      log:error(error)
    end
    return
  end

  -- Return the output
  file = io.open(temp_output, "r")
  if file then
    local contents = file:read("*all")
    log:debug('Command output: "%s"', contents)
    file:close()
    return contents
  else
    log:error("Failed to read output file")
    return
  end
end

return M
