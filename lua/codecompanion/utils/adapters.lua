local M = {}

---Get the indexes of all of the system prompts in the chat buffer
---@param messages table
---@return table|nil
function M.get_system_prompts(messages)
  local prompts = {}
  for i = 1, #messages do
    if messages[i].role == "system" then
      table.insert(prompts, i)
    end
  end

  if #prompts > 0 then
    return prompts
  end
end

---Takes multiple user messages and merges them into a single message
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
          base_tbl[name].schema = vim.tbl_deep_extend("force", base_tbl.adapters[name].schema, adapter.schema)
        end
      end
    end
  end
end

return M
