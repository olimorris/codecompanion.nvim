local files = require("codecompanion.utils.files")

---@class codecompanion.LogHandler
---@field type string
---@field level integer
---@field formatter fun(level: integer, msg: string, ...: any)
---@field handle fun(level: integer, text: string)
local LogHandler = {}

local levels_reverse = {}
for k, v in pairs(vim.log.levels) do
  levels_reverse[v] = k
end

function LogHandler.new(opts)
  vim.validate({
    type = { opts.type, "s" },
    handle = { opts.handle, "f" },
    formatter = { opts.formatter, "f" },
    level = { opts.level, "n", true },
  })
  return setmetatable({
    type = opts.type,
    handle = opts.handle,
    formatter = opts.formatter,
    level = opts.level or vim.log.levels.INFO,
  }, { __index = LogHandler })
end

function LogHandler:log(level, msg, ...)
  if self.level <= level then
    local text = self.formatter(level, msg, ...)
    self.handle(level, text)
  end
end

local function default_formatter(level, msg, ...)
  local args = vim.F.pack_len(...)
  for i = 1, args.n do
    local v = args[i]
    if type(v) == "table" then
      args[i] = vim.inspect(v)
    elseif v == nil then
      args[i] = "nil"
    end
  end
  local ok, text = pcall(string.format, msg, vim.F.unpack_len(args))
  if ok then
    local str_level = levels_reverse[level]
    return string.format("[%s] %s\n%s", str_level, os.date("%Y-%m-%d %H:%M:%S"), text)
  else
    return string.format("[ERROR] error formatting log line: '%s' args %s", msg, vim.inspect(args))
  end
end

---@param opts table
---@return codecompanion.LogHandler
local function create_file_handler(opts)
  vim.validate({
    filename = { opts.filename, "s" },
  })
  local ok, stdpath = pcall(vim.fn.stdpath, "log")
  if not ok then
    stdpath = vim.fn.stdpath("cache")
  end
  local filepath = files.join(stdpath, opts.filename)
  local logfile, openerr = io.open(filepath, "a+")
  if not logfile then
    local err_msg = string.format("Failed to open the CodeCompanion log file: %s", openerr)
    vim.notify(err_msg, vim.log.levels.ERROR)
    opts.handle = function() end
  else
    opts.handle = function(level, text)
      logfile:write(text)
      logfile:write("\n")
      logfile:flush()
    end
  end
  return LogHandler.new(opts)
end

---@param opts table
---@return codecompanion.LogHandler
local function create_notify_handler(opts)
  opts.handle = function(level, text)
    vim.notify(text, level)
  end
  return LogHandler.new(opts)
end

---@param opts table
---@return codecompanion.LogHandler
local function create_echo_handler(opts)
  opts.handle = function(level, text)
    local hl = "Normal"
    if level == vim.log.levels.ERROR then
      hl = "DiagnosticError"
    elseif level == vim.log.levels.WARN then
      hl = "DiagnosticWarn"
    end
    vim.api.nvim_echo({ { text, hl } }, true, {})
  end
  return LogHandler.new(opts)
end

---@return codecompanion.LogHandler
local function create_null_handler()
  return LogHandler.new({
    formatter = function() end,
    handle = function() end,
  })
end

---@param opts table
---@return codecompanion.LogHandler
local function create_handler(opts)
  vim.validate({
    type = { opts.type, "s" },
  })
  if not opts.formatter then
    opts.formatter = default_formatter
  end
  if opts.type == "file" then
    return create_file_handler(opts)
  elseif opts.type == "notify" then
    return create_notify_handler(opts)
  elseif opts.type == "echo" then
    return create_echo_handler(opts)
  else
    vim.notify(string.format("Unknown log handler %s", opts.type), vim.log.levels.ERROR)
    return create_null_handler()
  end
end

---@class codecompanion.Logger
---@field handlers codecompanion.LogHandler[]
local Logger = {}

---@class codecompanion.LoggerArgs
---@field handlers codecompanion.LogHandler[]
---@field level nil|integer

---@param opts codecompanion.LoggerArgs
function Logger.new(opts)
  vim.validate({
    handlers = { opts.handlers, "t" },
    level = { opts.level, "n", true },
  })
  local handlers = {}
  for _, defn in ipairs(opts.handlers) do
    table.insert(handlers, create_handler(defn))
  end
  local log = setmetatable({
    handlers = handlers,
  }, { __index = Logger })
  if opts.level then
    log:set_level(opts.level)
  end
  return log
end

---@param level integer
function Logger:set_level(level)
  for _, handler in ipairs(self.handlers) do
    handler.level = level
  end
end

---@return codecompanion.LogHandler[]
function Logger:get_handlers()
  return self.handlers
end

---@param level integer
---@param msg string
---@param ... any[]
function Logger:log(level, msg, ...)
  for _, handler in ipairs(self.handlers) do
    handler:log(level, msg, ...)
  end
end

---@param msg string
---@param ... any
function Logger:trace(msg, ...)
  self:log(vim.log.levels.TRACE, msg, ...)
end

---@param msg string
---@param ... any
function Logger:debug(msg, ...)
  self:log(vim.log.levels.DEBUG, msg, ...)
end

---@param msg string
---@param ... any
function Logger:info(msg, ...)
  self:log(vim.log.levels.INFO, msg, ...)
end

---@param msg string
---@param ... any
function Logger:warn(msg, ...)
  self:log(vim.log.levels.WARN, msg, ...)
end

---@param msg string
---@param ... any
function Logger:error(msg, ...)
  self:log(vim.log.levels.ERROR, msg, ...)
end

---@generic T : any
---@param cb T
---@param message nil|string
---@return T
function Logger:wrap_cb(cb, message)
  return function(err, ...)
    if err then
      self:error(message or "Error: %s", err)
    end
    return cb(err, ...)
  end
end

local root = Logger.new({
  handlers = {
    {
      type = "echo",
      level = vim.log.levels.WARN,
    },
  },
})

---@type codecompanion.Logger
local M = {}

M.new = Logger.new

M.get_logfile = function()
  local ok, stdpath = pcall(vim.fn.stdpath, "log")
  if not ok then
    stdpath = vim.fn.stdpath("cache")
  end

  return files.join(stdpath, "codecompanion.log")
end

---@param logger codecompanion.Logger
M.set_root = function(logger)
  root = logger
end

---@return codecompanion.Logger
M.get_root = function()
  return root
end

setmetatable(M, {
  __index = function(_, key)
    return root[key]
  end,
})

return M
