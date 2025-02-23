---@class MockJob
---@field is_shutdown boolean
---@field _opts table
---@field _stdout_results table
---@field _stderr_results table
---@field _on_exit function
local MockJob = {}
MockJob.__index = MockJob

---Create a new mock job
---@param opts table
---@return MockJob
function MockJob:new(opts)
  ---@type MockJob
  local job = setmetatable({
    is_shutdown = false,
    _opts = opts,
    _stdout_results = { "mocked stdout" },
    _stderr_results = {},
    _on_exit = opts.on_exit,
  }, self)

  return job
end

---Mock start function
---@return MockJob
function MockJob:start()
  -- Execute immediately instead of scheduling
  if self._on_exit then
    self._on_exit(self, 0)
  end
  return self
end

---Mock and_then_wrap function
---@param next_job MockJob
function MockJob:and_then_wrap(next_job)
  next_job:start()
end

---Mock shutdown function
function MockJob:shutdown()
  self.is_shutdown = true
end

return MockJob
