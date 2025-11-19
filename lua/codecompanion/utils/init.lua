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
  if type(t) ~= "table" then
    return false
  end
  if vim.islist then
    return vim.islist(t)
  end
  return vim.tbl_islist(t)
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
---@param replacements {placeholder: string, replacement: string}
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
---@param bufnr number
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

---Add a callback to a set of callbacks
---@param callbacks table|nil The existing callbacks
---@param event string The event to add the callback to
---@param fn function The callback function
function M.callbacks_extend(callbacks, event, fn)
  callbacks = callbacks or {}
  local existing = callbacks[event]
  if not existing then
    callbacks[event] = fn
  elseif type(existing) == "function" then
    callbacks[event] = { existing, fn }
  else
    table.insert(existing, fn)
  end
  return callbacks
end

---Resolve a nested table value using a dot-separated path string
---@param tbl table The table to traverse
---@param path string The dot-separated path (e.g. "strategies.chat.tools.memory")
---@return any|nil The resolved value, or nil if the path doesn't exist
function M.resolve_nested_value(tbl, path)
  local parts = vim.split(path, ".", { plain = true })
  local resolved = tbl
  for _, part in ipairs(parts) do
    resolved = resolved[part]
    if not resolved then
      return nil
    end
  end
  return resolved
end

---Convert a word to singular or plural form based on count
---@param count number The count to determine singular or plural
---@param word string The base word (singular form)
---@return string The word with "s" appended if count ~= 1, or the original word if inputs are invalid
function M.pluralize(count, word)
  if type(count) ~= "number" or type(word) ~= "string" then
    return word or "item"
  end
  return count == 1 and word or word .. "s"
end

return M
