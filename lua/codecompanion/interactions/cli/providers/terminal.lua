-- Send queue and readiness detection inspired by sidekick.nvim
-- https://github.com/folke/sidekick.nvim

local Queue = require("codecompanion.utils.queue")
local log = require("codecompanion.utils.log")

local api = vim.api

local CONSTANTS = {
  MAX_WAIT = 5000, -- ms before giving up waiting for terminal
  MIN_LINES = 5, -- non-empty lines before checking stability
  POLL_INTERVAL = 100, -- ms between readiness polls
  SEND_DELAY = 100, -- ms between consuming queue items
  STABLE_FOR = 500, -- ms of unchanged output to consider ready
}

---@class CodeCompanion.CLI.Provider
---@field agent table
---@field bufnr number
---@field chan number|nil
---@field consumer_timer uv.uv_timer_t|nil
---@field poll_timer uv.uv_timer_t|nil
---@field queue CodeCompanion.Queue
---@field ready boolean
local Terminal = {}

---@param args { bufnr: number, agent: table }
---@return CodeCompanion.CLI.Provider
function Terminal.new(args)
  local self = setmetatable({
    agent = args.agent,
    bufnr = args.bufnr,
    chan = nil,
    consumer_timer = nil,
    poll_timer = nil,
    queue = Queue.new(),
    ready = false,
  }, { __index = Terminal })
  ---@cast self CodeCompanion.CLI.Provider

  return self
end

---Start the terminal process and begin polling for readiness
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
          self:_close_timers()
        end,
      })
    end)
  end)

  if not ok then
    log:error("Failed to start CLI agent: %s", err)
    return false
  end

  if not self.chan or self.chan <= 0 then
    return false
  end

  self:_poll_until_ready()

  return true
end

---Queue text to send to the terminal (consumed once ready)
---@param text string
---@param opts? { submit: boolean }
---@return boolean
function Terminal:send(text, opts)
  if not self.chan then
    log:warn("CLI agent is not running")
    return false
  end

  self.queue:push({ text = text })
  if opts and opts.submit then
    self.queue:push({ enter = true })
  end

  if self.ready then
    self:_consume()
  end

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
  self:_close_timers()
  if self.chan then
    pcall(vim.fn.jobstop, self.chan)
    self.chan = nil
  end
end

---Count non-empty lines in the terminal buffer
---@private
---@return number
function Terminal:_count_lines()
  local lines = api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
  local count = 0
  for _, line in ipairs(lines) do
    if line ~= "" then
      count = count + 1
    end
  end
  return count
end

---Poll the terminal buffer until output has stabilized
---@private
function Terminal:_poll_until_ready()
  local started_at = vim.uv.hrtime()
  local last_count = 0
  local stable_since = nil

  self.poll_timer = vim.uv.new_timer()
  self.poll_timer:start(
    CONSTANTS.POLL_INTERVAL,
    CONSTANTS.POLL_INTERVAL,
    vim.schedule_wrap(function()
      if not self.bufnr or not api.nvim_buf_is_valid(self.bufnr) then
        return self:_on_ready()
      end

      if (vim.uv.hrtime() - started_at) / 1e6 > CONSTANTS.MAX_WAIT then
        return self:_on_ready()
      end

      local count = self:_count_lines()
      if count < CONSTANTS.MIN_LINES then
        return
      end

      if count ~= last_count then
        last_count = count
        stable_since = vim.uv.hrtime()
      elseif not stable_since then
        stable_since = vim.uv.hrtime()
      elseif (vim.uv.hrtime() - stable_since) / 1e6 >= CONSTANTS.STABLE_FOR then
        return self:_on_ready()
      end
    end)
  )
end

---Called when the terminal is ready to receive input
---@private
function Terminal:_on_ready()
  self.ready = true
  self:_close_timer("poll_timer")

  if not self.queue:is_empty() then
    self:_consume()
  end
end

---Start consuming queued items at a fixed interval
---@private
function Terminal:_consume()
  if self.consumer_timer then
    return
  end

  self.consumer_timer = vim.uv.new_timer()
  self.consumer_timer:start(
    0,
    CONSTANTS.SEND_DELAY,
    vim.schedule_wrap(function()
      if self.queue:is_empty() or not self.chan then
        self:_close_timer("consumer_timer")
        return
      end

      local item = self.queue:pop()
      if item.enter then
        vim.fn.chansend(self.chan, "\r")
      else
        local text = item.text:gsub("\r\n", "\n")
        vim.fn.chansend(self.chan, text)
      end
    end)
  )
end

---Close a single timer by field name
---@private
---@param field string
function Terminal:_close_timer(field)
  local timer = self[field]
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
  self[field] = nil
end

---Close all timers
---@private
function Terminal:_close_timers()
  self:_close_timer("poll_timer")
  self:_close_timer("consumer_timer")
end

return Terminal
