local M = {}

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

---Pop messages out of a table with a specific role
---@param messages table
---@param role string
---@return table
function M.pop_messages(messages, role)
  for i = #messages, 1, -1 do
    if messages[i].role == role then
      table.remove(messages, i)
    end
  end

  return messages
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
          content = table.concat(temp_msgs, " "),
        })
      end
      -- Start new accumulation for the current role
      temp_msgs = { trim_newlines(message.content) }
    end
    last_role = message.role
  end

  -- Add remaining accumulated messages
  if #temp_msgs > 0 then
    table.insert(new_msgs, {
      role = last_role,
      content = table.concat(temp_msgs, " "),
    })
  end

  return new_msgs
end

return M
