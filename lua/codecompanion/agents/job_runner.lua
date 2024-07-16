local Job = require("plenary.job")

local log = require("codecompanion.utils.log")

local M = {}

local stderr = {}
local stdout = {}
local last_execute = false
local status = ""

local api = vim.api

---@param bufnr number
local function announce_start(bufnr)
  api.nvim_exec_autocmds("User", { pattern = "CodeCompanionAgent", data = { bufnr = bufnr, status = "started" } })
end

---@param bufnr number
local function announce_end(bufnr)
  api.nvim_exec_autocmds("User", {
    pattern = "CodeCompanionAgent",
    data = { bufnr = bufnr, status = status, error = stderr, output = stdout, last_execute = last_execute },
  })
end

---Run the jobs
---@param cmds table
---@param chat CodeCompanion.Chat
---@param index number
---@return nil
local function run(cmds, chat, index)
  if index > #cmds then
    return
  end

  local cmd = cmds[index]

  log:debug("Running cmd: %s", cmd)

  local job = Job:new({
    command = cmd[1],
    args = { unpack(cmd, 2) }, -- args start from index 2
    on_exit = function(_, exit_code)
      run(cmds, chat, index + 1)

      vim.schedule(function()
        if _G.codecompanion_cancel_agent then
          return announce_end(chat.bufnr)
        end

        if index == #cmds then
          if exit_code ~= 0 then
            status = "error"
            log:error("Command failed: %s", stderr)
          end
          return announce_end(chat.bufnr)
        end
      end)
    end,
    on_stdout = function(_, data)
      vim.schedule(function()
        log:trace("stdout: %s", data)
        if index == #cmds then
          table.insert(stdout, data)
        end
      end)
    end,
    on_stderr = function(_, data)
      table.insert(stderr, data)
    end,
  })

  chat.current_agent = job
  job:start()
end

---Initiate the job runner
---@param cmds table
---@param chat CodeCompanion.Chat
---@param last_init boolean Whether this is the last agent in one conversation turn
---@return nil
function M.init(cmds, chat, last_init)
  -- Reset defaults
  status = "success"
  stderr = {}
  stdout = {}
  last_execute = last_init
  _G.codecompanion_cancel_agent = false

  announce_start(chat.bufnr)
  return run(cmds, chat, 1)
end

return M
