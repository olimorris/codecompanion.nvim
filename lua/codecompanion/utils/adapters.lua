local M = {}

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
