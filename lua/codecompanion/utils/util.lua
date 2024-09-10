local api = vim.api

local M = {}

---Fire an event
---@param event string
---@param opts? table
function M.fire(event, opts)
  opts = opts or {}
  api.nvim_exec_autocmds("User", { pattern = "CodeCompanion" .. event, data = opts })
end

---Make the first letter uppercase
---@param str string
---@return string
M.capitalize = function(str)
  return (str:gsub("^%l", string.upper))
end

---@param tbl table
---@return integer
M.count = function(tbl)
  local count = 0
  for _ in pairs(tbl) do
    count = count + 1
  end
  return count
end

---Check if a table is empty
---@param tbl? table
---@return boolean
M.is_empty = function(tbl)
  if tbl == nil then
    return true
  end

  return next(tbl) == nil
end

---Find a nested key in a table and return the index
---@param tbl table
---@param key any
---@param val any
---@return integer|nil
function M.find_key(tbl, key, val)
  for k, v in pairs(tbl) do
    if type(v) == "table" then
      if v[key] == val then
        return k
      else
        local result = M.find_key(v, key, val)
        if result then
          return k
        end
      end
    elseif k == key and v == val then
      return k
    end
  end
  return nil
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

---Replace any placeholders (e.g. ${placeholder}) in a string or table
---@param tbl table|string
---@param replacements table
---@return nil|string
function M.replace_placeholders(tbl, replacements)
  if type(tbl) == "string" then
    for placeholder, replacement in pairs(replacements) do
      tbl = tbl:gsub("%${" .. placeholder .. "}", replacement)
    end
    return tbl
  else
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

return M
