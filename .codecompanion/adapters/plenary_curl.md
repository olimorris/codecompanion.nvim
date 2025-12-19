# Plenary.Curl

The Plenary.Curl library:

````lua
--[[
Curl Wrapper

all curl methods accepts

  url          = "The url to make the request to.", (string)
  query        = "url query, append after the url", (table)
  body         = "The request body" (string/filepath/table)
  auth         = "Basic request auth, 'user:pass', or {"user", "pass"}" (string/array)
  form         = "request form" (table)
  raw          = "any additonal curl args, it must be an array/list." (array)
  dry_run      = "whether to return the args to be ran through curl." (boolean)
  output       = "where to download something." (filepath)
  timeout      = "request timeout in mseconds" (number)
  http_version = "HTTP version to use: 'HTTP/0.9', 'HTTP/1.0', 'HTTP/1.1', 'HTTP/2', or 'HTTP/3'" (string)
  proxy        = "[protocol://]host[:port] Use this proxy" (string)
  insecure     = "Allow insecure server connections" (boolean)

and returns table:

  exit    = "The shell process exit code." (number)
  status  = "The https response status." (number)
  headers = "The https response headers." (array)
  body    = "The http response body." (string)

see test/plenary/curl_spec.lua for examples.

author = github.com/tami5
]]
--

local util, parse = {}, {}

-- Helpers --------------------------------------------------
-------------------------------------------------------------
local F = require "plenary.functional"
local J = require "plenary.job"
local P = require "plenary.path"
local compat = require "plenary.compat"

-- Utils ----------------------------------------------------
-------------------------------------------------------------

util.url_encode = function(str)
  if type(str) ~= "number" then
    str = str:gsub("\r?\n", "\r\n")
    str = str:gsub("([^%w%-%.%_%~ ])", function(c)
      return string.format("%%%02X", c:byte())
    end)
    str = str:gsub(" ", "+")
    return str
  else
    return str
  end
end

util.kv_to_list = function(kv, prefix, sep)
  return compat.flatten(F.kv_map(function(kvp)
    return { prefix, kvp[1] .. sep .. kvp[2] }
  end, kv))
end

util.kv_to_str = function(kv, sep, kvsep)
  return F.join(
    F.kv_map(function(kvp)
      return kvp[1] .. kvsep .. util.url_encode(kvp[2])
    end, kv),
    sep
  )
end

util.gen_dump_path = function()
  local path
  local id = string.gsub("xxxx4xxx", "[xy]", function(l)
    local v = (l == "x") and math.random(0, 0xf) or math.random(0, 0xb)
    return string.format("%x", v)
  end)
  if P.path.sep == "\\" then
    path = string.format("%s\\AppData\\Local\\Temp\\plenary_curl_%s.headers", os.getenv "USERPROFILE", id)
  else
    local temp_dir = os.getenv "XDG_RUNTIME_DIR" or "/tmp"
    path = temp_dir .. "/plenary_curl_" .. id .. ".headers"
  end
  return { "-D", path }
end

-- Parsers ----------------------------------------------------
---------------------------------------------------------------

parse.headers = function(t)
  if not t then
    return
  end
  local upper = function(str)
    return string.gsub(" " .. str, "%W%l", string.upper):sub(2)
  end
  return util.kv_to_list(
    (function()
      local normilzed = {}
      for k, v in pairs(t) do
        normilzed[upper(k:gsub("_", "%-"))] = v
      end
      return normilzed
    end)(),
    "-H",
    ": "
  )
end

parse.data_body = function(t)
  if not t then
    return
  end
  return util.kv_to_list(t, "-d", "=")
end

parse.raw_body = function(xs)
  if not xs then
    return
  end
  if type(xs) == "table" then
    return parse.data_body(xs)
  else
    return { "--data-raw", xs }
  end
end

parse.form = function(t)
  if not t then
    return
  end
  return util.kv_to_list(t, "-F", "=")
end

parse.curl_query = function(t)
  if not t then
    return
  end
  return util.kv_to_str(t, "&", "=")
end

parse.method = function(s)
  if not s then
    return
  end
  if s ~= "head" then
    return { "-X", string.upper(s) }
  else
    return { "-I" }
  end
end

parse.file = function(p)
  if not p then
    return
  end
  return { "-d", "@" .. P.expand(P.new(p)) }
end

parse.auth = function(xs)
  if not xs then
    return
  end
  return { "-u", type(xs) == "table" and util.kv_to_str(xs, nil, ":") or xs }
end

parse.url = function(xs, q)
  if not xs then
    return
  end
  q = parse.curl_query(q)
  if type(xs) == "string" then
    return q and xs .. "?" .. q or xs
  elseif type(xs) == "table" then
    error "Low level URL definition is not supported."
  end
end

parse.accept_header = function(s)
  if not s then
    return
  end
  return { "-H", "Accept: " .. s }
end

parse.http_version = function(s)
  if not s then
    return
  end
  if s == "HTTP/0.9" or s == "HTTP/1.0" or s == "HTTP/1.1" or s == "HTTP/2" or s == "HTTP/3" then
    s = s:lower()
    s = s:gsub("/", "")
    return { "--" .. s }
  else
    error "Unknown HTTP version."
  end
end

-- Parse Request -------------------------------------------
------------------------------------------------------------
parse.request = function(opts)
  if opts.body then
    local b = opts.body
    local silent_is_file = function()
      local status, result = pcall(P.is_file, P.new(b))
      return status and result
    end
    opts.body = nil
    if type(b) == "table" then
      opts.data = b
    elseif silent_is_file() then
      opts.in_file = b
    elseif type(b) == "string" then
      opts.raw_body = b
    end
  end
  local result = { "-sSL", opts.dump }
  local append = function(v)
    if v then
      table.insert(result, v)
    end
  end

  if opts.insecure then
    table.insert(result, "--insecure")
  end
  if opts.proxy then
    table.insert(result, { "--proxy", opts.proxy })
  end
  if opts.compressed then
    table.insert(result, "--compressed")
  end
  append(parse.method(opts.method))
  append(parse.headers(opts.headers))
  append(parse.accept_header(opts.accept))
  append(parse.raw_body(opts.raw_body))
  append(parse.data_body(opts.data))
  append(parse.form(opts.form))
  append(parse.file(opts.in_file))
  append(parse.auth(opts.auth))
  append(parse.http_version(opts.http_version))
  append(opts.raw)
  if opts.output then
    table.insert(result, { "-o", opts.output })
  end
  table.insert(result, parse.url(opts.url, opts.query))
  return compat.flatten(result), opts
end

-- Parse response ------------------------------------------
------------------------------------------------------------
parse.response = function(lines, dump_path, code)
  local headers = P.readlines(dump_path)
  local status = nil
  local processed_headers = {}

  -- Process headers in a single pass
  for _, line in ipairs(headers) do
    local status_match = line:match "^HTTP/%S*%s+(%d+)"
    if status_match then
      status = tonumber(status_match)
    elseif line ~= "" then
      table.insert(processed_headers, line)
    end
  end

  local body = F.join(lines, "\n")
  vim.loop.fs_unlink(dump_path)

  return {
    status = status or 0,
    headers = processed_headers,
    body = body,
    exit = code,
  }
end

local request = function(specs)
  local response = {}
  local args, opts = parse.request(vim.tbl_extend("force", {
    compressed = package.config:sub(1, 1) ~= "\\",
    dry_run = false,
    dump = util.gen_dump_path(),
  }, specs))

  if opts.dry_run then
    return args
  end

  local job_opts = {
    command = vim.g.plenary_curl_bin_path or "curl",
    args = args,
  }

  if opts.stream then
    job_opts.on_stdout = opts.stream
  end

  job_opts.on_exit = function(j, code)
    if code ~= 0 then
      local stderr = vim.inspect(j:stderr_result())
      local message = string.format("%s %s - curl error exit_code=%s stderr=%s", opts.method, opts.url, code, stderr)
      if opts.on_error then
        return opts.on_error {
          message = message,
          stderr = stderr,
          exit = code,
        }
      else
        error(message)
      end
    end
    local output = parse.response(j:result(), opts.dump[2], code)
    if opts.callback then
      return opts.callback(output)
    else
      response = output
    end
  end
  local job = J:new(job_opts)

  if opts.callback or opts.stream then
    job:start()
    return job
  else
    local timeout = opts.timeout or 10000
    job:sync(timeout)
    return response
  end
end

-- Main ----------------------------------------------------
------------------------------------------------------------
return (function()
  local partial = function(method)
    return function(url, opts)
      local spec = {}
      opts = opts or {}
      if type(url) == "table" then
        opts = url
        spec.method = method
      else
        spec.url = url
        spec.method = method
      end
      opts = method == "request" and opts or (vim.tbl_extend("keep", opts, spec))
      return request(opts)
    end
  end
  return {
    get = partial "get",
    post = partial "post",
    put = partial "put",
    head = partial "head",
    patch = partial "patch",
    delete = partial "delete",
    request = partial "request",
  }
end)()
````
