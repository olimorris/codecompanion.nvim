local files = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

local fmt = string.format

local M = {}

---@class CodeCompanion.Curl.Opts
---@field url string
---@field method? "GET"|"POST"
---@field headers? table<string, string>
---@field body? string
---@field body_file? string
---@field output? string
---@field raw? string[]
---@field insecure? boolean
---@field proxy? string
---@field compressed? boolean
---@field timeout? number
---@field stream? fun(err: nil, line: string)
---@field callback? fun(response: CodeCompanion.Curl.Response)
---@field on_error? fun(err: CodeCompanion.Curl.Error)

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

---Read the status and header lines curl dumped, keeping every response's headers across redirects
---@param headers_file string
---@return number status, string[] headers
local function read_headers(headers_file)
  local status, headers = 0, {}
  local ok, content = pcall(files.read, headers_file)
  files.delete(headers_file)
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

  if result.code ~= 0 or result.signal ~= 0 then
    files.delete(request.headers_file)
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

  local status, headers = read_headers(request.headers_file)
  return { status = status, headers = headers, body = result.stdout or "", exit = result.code }
end

---@param request CodeCompanion.Curl.Request
---@param opts { system_opts: vim.SystemOpts, on_exit?: fun(result: vim.SystemCompleted) }
---@return vim.SystemObj|nil, CodeCompanion.Curl.Error|nil
local function spawn(request, opts)
  local ok, process = pcall(vim.system, request.args, opts.system_opts, opts.on_exit)
  if not ok then
    local message = fmt("%s %s - could not start curl: %s", request.method, request.url, process)
    return nil, { message = message, stderr = tostring(process), exit = -1 }
  end
  return process
end

---Collect stdout and pass each complete line to `on_line` on the main loop
---@param opts { chunks: string[], on_line?: fun(err: nil, line: string) }
---@return fun(err?: string, chunk?: string)
local function read_stdout(opts)
  local partial = ""

  return function(_, chunk)
    if chunk then
      table.insert(opts.chunks, chunk)
    end
    if not opts.on_line then
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
        opts.on_line(nil, line)
      end
    end)
  end
end

---@param opts { request: CodeCompanion.Curl.Request, result: vim.SystemCompleted }
local function finish_async(opts)
  local request = opts.request
  local response, err = build_response(opts)
  if err and request.on_error then
    return request.on_error(err)
  elseif err then
    return log:error("[curl] %s", err.message)
  end
  if request.callback then
    request.callback(response)
  end
end

---@param request CodeCompanion.Curl.Request
---@return CodeCompanion.Curl.Job|nil, CodeCompanion.Curl.Error|nil
local function request_async(request)
  local chunks = {}

  local process, err = spawn(request, {
    system_opts = {
      stdin = request.body,
      stdout = read_stdout({ chunks = chunks, on_line = request.stream }),
      timeout = request.timeout,
    },
    on_exit = function(result)
      result.stdout = table.concat(chunks)
      vim.schedule(function()
        finish_async({ request = request, result = result })
      end)
    end,
  })
  if not process then
    return nil, err
  end

  return {
    args = request.args,
    shutdown = function()
      if not process:is_closing() then
        process:kill("sigterm")
      end
    end,
  }
end

---@param request CodeCompanion.Curl.Request
---@return CodeCompanion.Curl.Response|nil, CodeCompanion.Curl.Error|nil
local function request_sync(request)
  local process, err = spawn(request, { system_opts = { stdin = request.body } })
  if not process then
    return nil, err
  end
  return build_response({ request = request, result = process:wait(request.timeout or 10000) })
end

---Make a request, blocking until it completes unless a `callback` or `stream` is given
---@param opts CodeCompanion.Curl.Opts
---@return CodeCompanion.Curl.Response|CodeCompanion.Curl.Job|nil, CodeCompanion.Curl.Error|nil
function M.request(opts)
  local request = vim.tbl_extend("force", { method = "GET" }, opts) --[[@as CodeCompanion.Curl.Request]]
  request.method = request.method:upper()
  request.headers_file = vim.fn.tempname() .. ".headers"
  request.args = build_args(request)

  if request.callback or request.stream then
    return request_async(request)
  end
  return request_sync(request)
end

---@param opts CodeCompanion.Curl.Opts
---@return CodeCompanion.Curl.Response|CodeCompanion.Curl.Job|nil, CodeCompanion.Curl.Error|nil
function M.get(opts)
  return M.request(vim.tbl_extend("force", opts, { method = "GET" }))
end

---@param opts CodeCompanion.Curl.Opts
---@return CodeCompanion.Curl.Response|CodeCompanion.Curl.Job|nil, CodeCompanion.Curl.Error|nil
function M.post(opts)
  return M.request(vim.tbl_extend("force", opts, { method = "POST" }))
end

return M
