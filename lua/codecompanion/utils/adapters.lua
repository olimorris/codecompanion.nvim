local Path = require("plenary.path")

local M = {}

---Ensure a table is a proper array (with sequential integer keys starting from 1)
---@param tbl table The table to convert
---@return table The same table converted to an array
function M.ensure_array(tbl)
  local islist = vim.islist or vim.tbl_islist ---@type function

  if islist(tbl) then
    return tbl
  end

  if vim.tbl_count(tbl) == 0 then
    return tbl
  end

  -- Convert to array
  local array = {}
  for _, v in pairs(tbl) do
    table.insert(array, v)
  end

  -- Clear original table and refill with array values
  for k in pairs(tbl) do
    tbl[k] = nil
  end

  for i, v in ipairs(array) do
    tbl[i] = v
  end

  return tbl
end

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

---Get the indexes for messages with a specific role
---@param role string
---@param messages table
---@return table|nil
function M.get_msg_index(role, messages)
  local prompts = {}
  for i = 1, #messages do
    if messages[i].role == role then
      table.insert(prompts, i)
    end
  end

  if #prompts > 0 then
    return prompts
  end
end

---Pluck messages from a table with a specific role
---@param messages table
---@param role string
---@return table
function M.pluck_messages(messages, role)
  local output = {}

  for _, message in ipairs(messages) do
    if message.role == role then
      table.insert(output, message)
    end
  end

  return output
end

---Merge consecutive messages with the same role, together
---@param messages table
---@return table
function M.merge_messages(messages)
  return vim.iter(messages):fold({}, function(acc, msg)
    local last = acc[#acc]
    if last and last.role == msg.role then
      last.content = last.content .. "\n\n" .. msg.content
    else
      table.insert(acc, { role = msg.role, content = msg.content })
    end
    return acc
  end)
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

return M
