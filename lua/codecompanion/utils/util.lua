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

---@param t table
---@return integer
M.count = function(t)
  local count = 0
  for _ in pairs(t) do
    count = count + 1
  end
  return count
end

---Check if a table is empty
---@param t? table
---@return boolean
M.is_empty = function(t)
  if t == nil then
    return true
  end

  return next(t) == nil
end

---Check if a table is an array
---@param t table
---@return boolean
M.is_array = function(t)
  if type(t) ~= "table" then
    return false
  end
  local i = 0
  for _ in pairs(t) do
    i = i + 1
    if t[i] == nil then
      return false
    end
  end
  return true
end

---Find a nested key in a table and return the index
---@param t table
---@param key any
---@param val any
---@return integer|nil
function M.find_key(t, key, val)
  for k, v in pairs(t) do
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
---@param t table|string
---@param replacements table
---@return nil|string
function M.replace_placeholders(t, replacements)
  if type(t) == "string" then
    for placeholder, replacement in pairs(replacements) do
      t = t:gsub("%${" .. placeholder .. "}", replacement)
    end
    return t
  else
    for key, value in pairs(t) do
      if type(value) == "table" then
        M.replace_placeholders(value, replacements)
      elseif type(value) == "string" then
        for placeholder, replacement in pairs(replacements) do
          value = value:gsub("%${" .. placeholder .. "}", replacement)
        end
        t[key] = value
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

---Set an option in Neovim
---@param bufnr integer
---@param opt string
---@param value any
function M.set_option(bufnr, opt, value)
  if vim.api.nvim_set_option_value then
    return vim.api.nvim_set_option_value(opt, value, {
      buf = bufnr,
    })
  end
  if vim.api.nvim_buf_set_option then
    return vim.api.nvim_buf_set_option(bufnr, opt, value)
  end
end

return M
