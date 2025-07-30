local adapter_utils = require("codecompanion.utils.adapters")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.ACPClient
---@field adapter CodeCompanion.ACPAdapter
---@field static table
---@field opts nil|table
local Client = {}
Client.static = {}

-- Static options for easier testing/mocking
Client.static.opts = {
  jobstart = { default = vim.fn.jobstart },
  chansend = { default = vim.fn.chansend },
  jobstop = { default = vim.fn.jobstop },
  schedule = { default = vim.schedule },
  encode = { default = vim.json.encode },
  decode = { default = vim.json.decode },
}

local function transform_static(opts)
  local ret = {}
  for k, v in pairs(Client.static.opts) do
    if opts and opts[k] ~= nil then
      ret[k] = opts[k]
    else
      ret[k] = v.default
    end
  end
  return ret
end

---@class CodeCompanion.ACPClientArgs
---@field adapter CodeCompanion.ACPAdapter
---@field opts? table

---@param args CodeCompanion.ACPClientArgs
---@return CodeCompanion.ACPClient
function Client.new(args)
  args = args or {}

  return setmetatable({
    adapter = args.adapter,
    opts = args.opts or transform_static(args.opts),
  }, { __index = Client })
end

---Start the ACP process
---@return CodeCompanion.ACPClient
function Client:start()
  -- Copy adapter and process env vars (like HTTP)
  local adapter = vim.deepcopy(self.adapter)

  if adapter.handlers and adapter.handlers.setup then
    local ok = adapter.handlers.setup(adapter)
    if not ok then
      return log:error("Failed to setup adapter")
    end
  end

  adapter = adapter_utils.get_env_vars(adapter)

  local job_opts = {
    stdin = "pipe",
    stdout = "pipe",
    stderr = "pipe",
    env = adapter.env_replaced or {},
    on_stdout = function(_, data, _)
      self:_handle_stdout(data)
    end,
    on_stderr = function(_, data, _)
      self:_handle_stderr(data)
    end,
    on_exit = function(_, code, _)
      self:_handle_exit(code)
    end,
  }

  local command = adapter_utils.set_env_vars(adapter, adapter.command)

  self.job_handle = self.opts.jobstart(command, job_opts)
  self.next_id = 1
  self.pending = {}
  self.stdout_buffer = ""

  if self.job_handle <= 0 then
    log:error("Failed to start ACP client: %s", adapter.name)
    return self
  end

  return self
end

---Stop the ACP process
---@return boolean success
function Client:stop() end

---Check if the client is running
---@return boolean
function Client:is_running() end

function Client:request() end

return Client
