local api = vim.api

local M = {}

---Make the first letter uppercase
---@param str string
---@return string
M.capitalize = function(str)
  return (str:gsub("^%l", string.upper))
end

---@param table table
---@return integer
M.count = function(table)
  local count = 0
  for _ in pairs(table) do
    count = count + 1
  end

  return count
end

---@param table table
---@param value string
---@return boolean
M.contains = function(table, value)
  for _, v in pairs(table) do
    if v == value then
      return true
    end
  end
  return false
end

M._noop = function() end

---@param name string
---@return nil
M.set_dot_repeat = function(name)
  vim.go.operatorfunc = "v:lua.require'codecompanion.utils.util'._noop"
  vim.cmd.normal({ args = { "g@l" }, bang = true })
  vim.go.operatorfunc = string.format("v:lua.require'codecompanion'.%s", name)
end

---@param tbl table
---@param replacements table
---@return nil
function M.replace_placeholders(tbl, replacements)
  for key, value in pairs(tbl) do
    if type(value) == "table" then
      M.replace_placeholders(value, replacements)
    elseif type(value) == "string" then
      for placeholder, replacement in pairs(replacements) do
        value = value:gsub("%${" .. placeholder .. "}", replacement)
      end
      tbl[key] = value
    end
  end
end

---@param msg string
---@param vars table
---@param mapping table
---@return string
function M.replace_vars(msg, vars, mapping)
  local replacements = {}
  for _, var_name in ipairs(vars) do
    -- Check if the variable exists in the mapping
    if mapping[var_name] then
      table.insert(replacements, mapping[var_name])
    else
      error("Variable '" .. var_name .. "' not found in the mapping.")
    end
  end
  return string.format(msg, unpack(replacements))
end

---Check if value starts with "cmd:"
---@param value string
---@return boolean
function M.is_cmd_var(value)
  return value:match("^cmd:")
end

return M
