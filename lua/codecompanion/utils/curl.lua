local files = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

local fmt = string.format

local M = {}

---@class CodeCompanion.Curl.Opts
---@field body? string
---@field body_file? string
---@field callback? fun(response: CodeCompanion.Curl.Response)
---@field compressed? boolean
---@field headers? table<string, string>
---@field insecure? boolean
---@field method? "GET"|"POST"
---@field on_error? fun(err: CodeCompanion.Curl.Error)
---@field output? string
---@field proxy? string
---@field raw? string[]
---@field stream? fun(line: string)
---@field timeout? number
---@field url string

---@class CodeCompanion.Curl.Request : CodeCompanion.Curl.Opts
---@field method "GET"|"POST"
---@field headers_file string
---@field args string[]

---@class CodeCompanion.Curl.Response
---@field status number
---@field headers string[]
---@field body string
---@field exit number

---@class CodeCompanion.Curl.Error
---@field message string
---@field stderr string
---@field exit number

---@class CodeCompanion.Curl.Job
---@field args string[]
---@field shutdown fun()

---@param request CodeCompanion.Curl.Request
---@return string[]
local function build_args(request)
  local args = { "curl", "-sSL", "--dump-header", request.headers_file, "--request", request.method }

  if request.compressed then
    table.insert(args, "--compressed")
  end
  if request.insecure then
    table.insert(args, "--insecure")
  end
  if request.proxy then
    vim.list_extend(args, { "--proxy", request.proxy })
  end
  for name, value in pairs(request.headers or {}) do
    vim.list_extend(args, { "--header", name .. ": " .. tostring(value) })
  end
  if request.body_file then
    vim.list_extend(args, { "--data-binary", "@" .. request.body_file })
  elseif request.body then
    vim.list_extend(args, { "--data-binary", "@-" })
  end
  if request.output then
    vim.list_extend(args, { "--output", request.output })
  end
  vim.list_extend(args, request.raw or {})
  table.insert(args, request.url)

  return args
end

---@param headers_file string
---@return number status, string[] headers
local function read_headers(headers_file)
  local status, headers = 0, {}
  local ok, content = pcall(files.read, headers_file)
  if not ok then
    return status, headers
  end

  for _, line in ipairs(vim.split(content, "\r?\n")) do
    local code = line:match("^HTTP/%S+%s+(%d+)")
    if code then
      status = tonumber(code) --[[@as number]]
    elseif line ~= "" then
      table.insert(headers, line)
    end
  end

  return status, headers
end

---@param opts { request: CodeCompanion.Curl.Request, result: vim.SystemCompleted }
---@return CodeCompanion.Curl.Response|nil, CodeCompanion.Curl.Error|nil
local function build_response(opts)
  local request, result = opts.request, opts.result
  local status, headers = read_headers(request.headers_file)
  files.delete(request.headers_file)

  if result.code ~= 0 or result.signal ~= 0 then
    local stderr = result.stderr or ""
    local message = fmt(
      "%s %s - curl error exit_code=%d signal=%d stderr=%s",
      request.method,
      request.url,
      result.code,
      result.signal,
      stderr
    )
    return nil, { message = message, stderr = stderr, exit = result.code }
  end

  return { status = status, headers = headers, body = result.stdout or "", exit = result.code }
end

---@param request CodeCompanion.Curl.Request
---@param opts? { stdout?: fun(err?: string, chunk?: string) }
---@param on_exit? fun(result: vim.SystemCompleted)
---@return vim.SystemObj|nil, CodeCompanion.Curl.Error|nil
local function spawn(request, opts, on_exit)
  opts = opts or {}
  local system_opts = { stdin = request.body, stdout = opts.stdout, timeout = request.timeout }
  local ok, process = pcall(vim.system, request.args, system_opts, on_exit)
  if not ok then
    local message = fmt("%s %s - could not start curl: %s", request.method, request.url, process)
    return nil, { message = message, stderr = tostring(process), exit = -1 }
  end

  return process
end

---Collect stdout and pass each complete line to the request's `stream` on the main loop
---@param opts { request: CodeCompanion.Curl.Request, chunks: string[] }
---@return fun(err?: string, chunk?: string)
local function read_stdout(opts)
  local partial = ""

  return function(_, chunk)
    if chunk then
      table.insert(opts.chunks, chunk)
    end
    if not opts.request.stream then
      return
    end

    local text = partial .. (chunk or "")
    if not chunk and text == "" then
      return
    end
    local lines = vim.split(text, "\n", { plain = true })
    partial = chunk and table.remove(lines) or ""

    vim.schedule(function()
      for _, line in ipairs(lines) do
        opts.request.stream(line)
      end
    end)
  end
end

---@param opts { request: CodeCompanion.Curl.Request, err: CodeCompanion.Curl.Error }
local function report_error(opts)
  if opts.request.on_error then
    return opts.request.on_error(opts.err)
  end
  log:error("[curl] %s", opts.err.message)
end

---@param opts { request: CodeCompanion.Curl.Request, result: vim.SystemCompleted }
local function report_result(opts)
  local response, err = build_response(opts)
  if err then
    return report_error({ request = opts.request, err = err })
  end
  ---@cast response CodeCompanion.Curl.Response
  if opts.request.callback then
    opts.request.callback(response)
  end
end

---@param request CodeCompanion.Curl.Request
---@return CodeCompanion.Curl.Job
local function async(request)
  local chunks = {}

  local process, err = spawn(request, { stdout = read_stdout({ request = request, chunks = chunks }) }, function(result)
    result.stdout = table.concat(chunks)
    vim.schedule(function()
      report_result({ request = request, result = result })
    end)
  end)

  if not process then
    ---@cast err CodeCompanion.Curl.Error
    vim.schedule(function()
      report_error({ request = request, err = err })
    end)
    return { args = request.args, shutdown = function() end }
  end

  return {
    args = request.args,
    shutdown = function()
      process:kill("sigterm")
    end,
  }
end

---@param request CodeCompanion.Curl.Request
---@return CodeCompanion.Curl.Response|nil, CodeCompanion.Curl.Error|nil
local function sync(request)
  local process, err = spawn(request)
  if not process then
    return nil, err
  end

  return build_response({ request = request, result = process:wait(request.timeout or 10000) })
end

---@param opts CodeCompanion.Curl.Opts
---@return CodeCompanion.Curl.Request
local function build_request(opts)
  local request = vim.tbl_extend("force", { method = "GET" }, opts) --[[@as CodeCompanion.Curl.Request]]
  request.method = request.method:upper()
  request.headers_file = vim.fn.tempname() .. ".headers"
  request.args = build_args(request)
  return request
end

---Make a request without blocking, passing the response to `callback` and each line to `stream`
---@param opts CodeCompanion.Curl.Opts
---@return CodeCompanion.Curl.Job
function M.request(opts)
  return async(build_request(opts))
end

---Make a request, blocking until it completes
---@param opts CodeCompanion.Curl.Opts
---@return CodeCompanion.Curl.Response|nil, CodeCompanion.Curl.Error|nil
function M.request_sync(opts)
  return sync(build_request(opts))
end

---@param opts CodeCompanion.Curl.Opts
---@return CodeCompanion.Curl.Job
function M.get(opts)
  return M.request(vim.tbl_extend("force", opts, { method = "GET" }))
end

---@param opts CodeCompanion.Curl.Opts
---@return CodeCompanion.Curl.Job
function M.post(opts)
  return M.request(vim.tbl_extend("force", opts, { method = "POST" }))
end

---@param opts CodeCompanion.Curl.Opts
---@return CodeCompanion.Curl.Response|nil, CodeCompanion.Curl.Error|nil
function M.get_sync(opts)
  return M.request_sync(vim.tbl_extend("force", opts, { method = "GET" }))
end

---@param opts CodeCompanion.Curl.Opts
---@return CodeCompanion.Curl.Response|nil, CodeCompanion.Curl.Error|nil
function M.post_sync(opts)
  return M.request_sync(vim.tbl_extend("force", opts, { method = "POST" }))
end

return M
