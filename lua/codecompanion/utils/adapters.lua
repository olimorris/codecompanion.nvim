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

---Takes consecutive messages and merges them into a single message
---@param messages table
---@return table
function M.merge_messages(messages)
  local new_msgs = {}
  local temp_msgs = {}
  local last_role = nil

  local function trim_newlines(message)
    return (message:gsub("^%s*\n\n", ""))
  end

  for _, message in ipairs(messages) do
    if message.role == last_role then
      -- Continue accumulating content for the same role
      table.insert(temp_msgs, trim_newlines(message.content))
    else
      -- If switching roles, flush accumulated messages from previous role
      if last_role ~= nil then
        table.insert(new_msgs, {
          role = last_role,
          content = table.concat(temp_msgs, "\n\n"),
        })
      end
      -- Start new accumulation for the current role
      temp_msgs = { trim_newlines(message.content) }
    end
    last_role = message.role
  end

  -- Add remaining accumulated messages
  if vim.tbl_count(temp_msgs) > 0 then
    table.insert(new_msgs, {
      role = last_role,
      content = table.concat(temp_msgs, "\n\n"),
    })
  end

  return new_msgs
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
