local Path = require("plenary.path")
local log = require("codecompanion.utils.log")

local M = {}

---Refresh when we should next check the model cache
---@param file string
---@param cache_for number
---@return number
function M.refresh_cache(file, cache_for)
  cache_for = cache_for or 1800
  local time = os.time() + cache_for
  Path.new(file):write(time, "w")
  return time
end

---Return when the model cache expires
---@param file string
---@return number
function M.cache_expires(file, cache_for)
  cache_for = cache_for or 1800
  local ok, expires = pcall(function()
    return Path.new(file):read()
  end)
  if not ok then
    expires = M.refresh_cache(file, cache_for)
  end
  expires = tonumber(expires)
  assert(expires, "Could not get the cache expiry time")
  return expires
end

---Check if the cache has expired
---@param file string
---@return boolean
function M.cache_expired(file)
  return os.time() > M.cache_expires(file)
end

---Extend a default adapter
---@param base_tbl table
---@param new_tbl table
---@return nil
function M.extend(base_tbl, new_tbl)
  for name, adapter in pairs(new_tbl) do
    if base_tbl[name] then
      if type(adapter) == "table" then
        base_tbl[name] = adapter
        if adapter.schema then
          base_tbl[name].schema = vim.tbl_deep_extend("force", base_tbl[name].schema, adapter.schema)
        end
      end
    end
  end
end

---Merge consecutive messages with the same role, together
---@param messages table
---@param allowed_keys? table Additional keys to preserve beyond role and content-
---@param ignored_roles? table Roles that should not be merged even if consecutive
---@return table
function M.merge_messages(messages, allowed_keys, ignored_roles)
  allowed_keys = allowed_keys or { "tool_calls", "tool_call_id" }
  ignored_roles = ignored_roles or { "tool" }

  local no_merge = {}
  for _, role in ipairs(ignored_roles) do
    no_merge[role] = true
  end

  local islist = vim.islist or vim.tbl_islist

  return vim.iter(messages):fold({}, function(acc, msg)
    local last = acc[#acc]
    if last and last.role == msg.role and not no_merge[msg.role] then
      local a, b = last.content, msg.content
      -- both strings: concatenate
      if type(a) == "string" and type(b) == "string" then
        last.content = a .. "\n\n" .. b
      -- both tables: flatten b into a
      elseif type(a) == "table" and type(b) == "table" then
        -- ensure lists
        if not islist(a) then
          a = { a }
        end
        if not islist(b) then
          b = { b }
        end
        for _, item in ipairs(b) do
          table.insert(a, item)
        end
        last.content = a
      -- mixed types: coerce to list and flatten
      else
        local list = {}
        if type(a) == "table" then
          for _, v in ipairs(a) do
            table.insert(list, v)
          end
        else
          table.insert(list, a)
        end
        if type(b) == "table" then
          for _, v in ipairs(b) do
            table.insert(list, v)
          end
        else
          table.insert(list, b)
        end
        last.content = list
      end

      -- preserve other allowed fields
      for _, key in ipairs(allowed_keys) do
        if msg[key] then
          last[key] = msg[key]
        end
      end
    else
      -- new entry
      local new_entry = {
        role = msg.role,
        content = msg.content,
      }
      for _, key in ipairs(allowed_keys) do
        if msg[key] then
          new_entry[key] = msg[key]
        end
      end
      table.insert(acc, new_entry)
    end
    return acc
  end)
end

---Consolidate system messages into a single message
---@param messages table
---@return table
function M.merge_system_messages(messages)
  local contents = vim
    .iter(messages)
    :filter(function(msg)
      return msg.role == "system"
    end)
    :map(function(msg)
      return msg.content
    end)
    :totable()
  local system_contents = table.concat(contents, " ")

  local cleaned_messages = vim
    .iter(messages)
    :filter(function(msg)
      return msg.role ~= "system"
    end)
    :totable()

  if #contents > 0 then
    table.insert(cleaned_messages, 1, { role = "system", content = system_contents })
  end
  return cleaned_messages
end

---Clean streaming data to be parsed as JSON. Typically streaming endpoints
---return invalid JSON such as `data: { "id": 12345}`
---@param data string | { body: string }
---@return string
function M.clean_streamed_data(data)
  if type(data) == "table" then
    return data.body
  end
  local find_json_start = string.find(data, "{") or 1
  return string.sub(data, find_json_start)
end

-------------------------------------------------------------------------------
-- Utility functions extracted from adapters/init.lua
------------------------------------------------------------------------------

---Check if a variable starts with "cmd:"
---@param var string
---@return boolean
local function is_cmd(var)
  return var:match("^cmd:")
end

---Check if the variable is an environment variable
---@param var string
---@return boolean
local function is_env_var(var)
  local found_var = os.getenv(var)
  if not found_var then
    return false
  end
  return true
end

---Run the command in the environment variable
---@param var string
---@return string|nil
local function run_cmd(var)
  log:trace("Detected cmd in environment variable")
  local cmd = var:sub(5)
  local handle = io.popen(cmd, "r")
  if handle then
    local result = handle:read("*a")
    log:trace("Executed cmd: %s", cmd)
    handle:close()
    local r = result:gsub("%s+$", "")
    return r
  else
    return log:error("Error: Could not execute cmd: %s", cmd)
  end
end

---Get the environment variable
---@param var string
---@return string|nil
local function get_env_var(var)
  log:trace("Fetching environment variable: %s", var)
  return os.getenv(var) or nil
end

---Get the schema value
---@param adapter table
---@param var string
---@return string|nil
local function get_schema(adapter, var)
  log:trace("Fetching variable from schema: %s", var)

  local keys = {}
  for key in var:gmatch("[^%.]+") do
    table.insert(keys, key)
  end

  local node = adapter
  for _, key in ipairs(keys) do
    if type(node) ~= "table" then
      return nil
    end
    node = node[key]
    if node == nil then
      return nil
    end
  end

  if not node then
    return
  end

  return node
end

---Replace a variable with its value e.g. "${var}" -> "value"
---@param adapter table
---@param str string
---@return string
local function replace_var(adapter, str)
  if type(str) ~= "string" then
    return str
  end

  local pattern = "${(.-)}"

  local result = str:gsub(pattern, function(var)
    return adapter.env_replaced[var]
  end)

  return result
end

---Get the variables from the env key of the adapter
---@param adapter table
---@return table
function M.get_env_vars(adapter)
  local env_vars = adapter.env or {}

  if not env_vars then
    return adapter
  end

  adapter.env_replaced = {}

  for k, v in pairs(env_vars) do
    if type(v) == "string" and is_cmd(v) then
      adapter.env_replaced[k] = run_cmd(v)
    elseif type(v) == "string" and is_env_var(v) then
      adapter.env_replaced[k] = get_env_var(v)
    elseif type(v) == "function" then
      adapter.env_replaced[k] = v(adapter)
    else
      local schema = get_schema(adapter, v)
      if schema then
        adapter.env_replaced[k] = schema
      else
        adapter.env_replaced[k] = v
      end
    end
  end

  return adapter
end

---Set env vars in a given object in the adapter
---@param adapter table
---@param object string|table
---@return string|table|nil
function M.set_env_vars(adapter, object)
  local obj_copy = vim.deepcopy(object)

  if type(obj_copy) == "string" then
    return replace_var(adapter, obj_copy)
  elseif type(obj_copy) == "table" then
    local replaced = {}
    for k, v in pairs(obj_copy) do
      if type(v) == "string" then
        replaced[k] = replace_var(adapter, v)
      elseif type(v) == "function" then
        replaced[k] = replace_var(adapter, v(adapter))
      else
        replaced[k] = v
      end
    end
    return replaced
  end
end

---Replace roles in the messages with the adapter's defined roles
---@param roles table The roles mapping, e.g. { user = "human", assistant = "ai" }
---@param messages table
---@return table
function M.map_roles(roles, messages)
  for _, message in ipairs(messages) do
    if message.role then
      message.role = roles[message.role:lower()] or message.role
    end
  end
  return messages
end

return M
