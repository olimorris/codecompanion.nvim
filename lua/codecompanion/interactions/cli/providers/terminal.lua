local log = require("codecompanion.utils.log")

local api = vim.api

---@class CodeCompanion.CLI.Provider
---@field bufnr number
---@field chan number|nil
---@field agent table
local Terminal = {}

---@param args { bufnr: number, agent: table }
---@return CodeCompanion.CLI.Provider
function Terminal.new(args)
  local self = setmetatable({
    bufnr = args.bufnr,
    agent = args.agent,
    chan = nil,
  }, { __index = Terminal })
  ---@cast self CodeCompanion.CLI.Provider

  return self
end

---Start the terminal process in the buffer
---@return boolean
function Terminal:start()
  local cmd = vim.deepcopy(self.agent.args or {})
  table.insert(cmd, 1, self.agent.cmd)

  local ok, err = pcall(function()
    api.nvim_buf_call(self.bufnr, function()
      self.chan = vim.fn.jobstart(cmd, {
        term = true,
        cwd = vim.fn.getcwd(),
        on_exit = function(_, exit_code, _)
          log:debug("CLI agent exited with code %d", exit_code)
          self.chan = nil
        end,
      })
    end)
  end)

  if not ok then
    log:error("Failed to start CLI agent: %s", err)
    return false
  end

  return self.chan ~= nil
end

---Send text to the terminal
---@param text string
---@return boolean
function Terminal:send(text)
  if not self.chan then
    log:warn("CLI agent is not running")
    return false
  end

  api.nvim_chan_send(self.chan, text .. "\n")
  return true
end

---Check if the process is still running
---@return boolean
function Terminal:is_running()
  return self.chan ~= nil
end

---Stop the terminal process
---@return nil
function Terminal:stop()
  if self.chan then
    pcall(vim.fn.jobstop, self.chan)
    self.chan = nil
  end
end

return Terminal
