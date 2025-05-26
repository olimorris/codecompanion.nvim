local api = vim.api

local M = {}

---Fire an event
---@param event string
---@param opts? table
function M.fire(event, opts)
  opts = opts or {}
  api.nvim_exec_autocmds("User", { pattern = "CodeCompanion" .. event, data = opts })
end

---Notify the user
---@param msg string
---@param level? number|string
---@return nil
function M.notify(msg, level)
  level = level or vim.log.levels.INFO
  return vim.notify(msg, level, {
    title = "CodeCompanion",
  })
end

---Get the Operating System
---@return string
function M.os()
  local os_name
  if vim.fn.has("win32") == 1 then
    os_name = "Windows"
  elseif vim.fn.has("macunix") == 1 then
    os_name = "macOS"
  elseif vim.fn.has("unix") == 1 then
    os_name = "Unix"
  else
    os_name = "Unknown"
  end
  return os_name
end

---Make the first letter uppercase
---@param str string
---@return string
M.capitalize = function(str)
  local result = str:gsub("^%l", string.upper)
  return result
end

---Check if a table is an array
---@param t table
---@return boolean
M.is_array = function(t)
  if type(t) == "table" and type(t[1]) == "table" then
    return true
  end
  return false
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
  vim.go.operatorfunc = "v:lua.require'codecompanion.utils'._noop"
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

---Safely get the filetype
---@param filetype string
---@return string
function M.safe_filetype(filetype)
  if filetype == "C++" then
    return "cpp"
  end
  return filetype
end

---Set an option in Neovim
---@param bufnr integer
---@param opt string
---@param value any
function M.set_option(bufnr, opt, value)
  if api.nvim_set_option_value then
    return api.nvim_set_option_value(opt, value, {
      buf = bufnr,
    })
  end
  if api.nvim_buf_set_option then
    return api.nvim_buf_set_option(bufnr, opt, value)
  end
end

---Make a timestamp relative
---@param timestamp number Unix timestamp
---@return string Relative time string (e.g. "5m", "2h")
function M.make_relative(timestamp)
  local now = os.time()
  local diff = now - timestamp

  if diff < 60 then
    return diff .. "s"
  elseif diff < 3600 then
    return math.floor(diff / 60) .. "m"
  elseif diff < 86400 then
    return math.floor(diff / 3600) .. "h"
  else
    return math.floor(diff / 86400) .. "d"
  end
end

return M
