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

---@param opts CodeCompanion.Curl.Opts
---@param headers_file string
---@return string[]
local function build_args(opts, headers_file)
  local args = { "curl", "-sSL", "--dump-header", headers_file, "--request", opts.method }

  if opts.compressed then
    table.insert(args, "--compressed")
  end
  if opts.insecure then
    table.insert(args, "--insecure")
  end
  if opts.proxy then
    vim.list_extend(args, { "--proxy", opts.proxy })
  end
  for name, value in pairs(opts.headers or {}) do
    vim.list_extend(args, { "--header", name .. ": " .. tostring(value) })
  end
  if opts.body_file then
    vim.list_extend(args, { "--data-binary", "@" .. opts.body_file })
  elseif opts.body then
    vim.list_extend(args, { "--data-binary", "@-" })
  end
  if opts.output then
    vim.list_extend(args, { "--output", opts.output })
  end
  vim.list_extend(args, opts.raw or {})
  table.insert(args, opts.url)

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
      status = tonumber(code)
    elseif line ~= "" then
      table.insert(headers, line)
    end
  end

  return status, headers
end

---@param opts CodeCompanion.Curl.Opts
---@param result vim.SystemCompleted
---@param headers_file string
---@param body string
---@return CodeCompanion.Curl.Response|nil, CodeCompanion.Curl.Error|nil
local function to_response(opts, result, headers_file, body)
  if result.code ~= 0 or result.signal ~= 0 then
    files.delete(headers_file)
    local stderr = result.stderr or ""
    return nil,
      {
        message = fmt(
          "%s %s - curl error exit_code=%d signal=%d stderr=%s",
          opts.method,
          opts.url,
          result.code,
          result.signal,
          stderr
        ),
        stderr = stderr,
        exit = result.code,
      }
  end

  local status, headers = read_headers(headers_file)
  return { status = status, headers = headers, body = body, exit = result.code }
end

---Collect stdout and pass each complete line to `on_line` on the main loop
---@param chunks string[]
---@param on_line? fun(err: nil, line: string)
---@return fun(err?: string, chunk?: string)
local function read_stdout(chunks, on_line)
  local partial = ""

  return function(_, chunk)
    if chunk then
      table.insert(chunks, chunk)
    end
    if not on_line then
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
        on_line(nil, line)
      end
    end)
  end
end

---@param opts CodeCompanion.Curl.Opts
---@param args string[]
---@param headers_file string
---@return CodeCompanion.Curl.Job
local function request_async(opts, args, headers_file)
  local chunks = {}

  local process = vim.system(args, {
    stdin = opts.body,
    stdout = read_stdout(chunks, opts.stream),
    timeout = opts.timeout,
  }, function(result)
    vim.schedule(function()
      local response, err = to_response(opts, result, headers_file, table.concat(chunks))
      if err and opts.on_error then
        return opts.on_error(err)
      elseif err then
        return log:error("[curl] %s", err.message)
      end
      if opts.callback then
        opts.callback(response)
      end
    end)
  end)

  return {
    args = args,
    shutdown = function()
      if not process:is_closing() then
        process:kill("sigterm")
      end
    end,
  }
end

---@param opts CodeCompanion.Curl.Opts
---@param args string[]
---@param headers_file string
---@return CodeCompanion.Curl.Response
local function request_sync(opts, args, headers_file)
  local result = vim.system(args, { stdin = opts.body }):wait(opts.timeout or 10000)
  local response, err = to_response(opts, result, headers_file, result.stdout or "")
  if err then
    error(err.message)
  end
  return response
end

---Make a request, blocking until it completes unless a `callback` or `stream` is given
---@param opts CodeCompanion.Curl.Opts
---@return CodeCompanion.Curl.Response|CodeCompanion.Curl.Job
function M.request(opts)
  opts = vim.tbl_extend("force", { method = "GET" }, opts)
  opts.method = opts.method:upper()

  local headers_file = vim.fn.tempname() .. ".headers"
  local args = build_args(opts, headers_file)

  if opts.callback or opts.stream then
    return request_async(opts, args, headers_file)
  end
  return request_sync(opts, args, headers_file)
end

---@param opts CodeCompanion.Curl.Opts
---@return CodeCompanion.Curl.Response|CodeCompanion.Curl.Job
function M.get(opts)
  return M.request(vim.tbl_extend("force", opts, { method = "GET" }))
end

---@param opts CodeCompanion.Curl.Opts
---@return CodeCompanion.Curl.Response|CodeCompanion.Curl.Job
function M.post(opts)
  return M.request(vim.tbl_extend("force", opts, { method = "POST" }))
end

return M
