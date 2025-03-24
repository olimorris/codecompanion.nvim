local M = {}

---@param data any
---@return string
M.encode = function(data)
  local output = vim.json.encode(data)
  -- Replace instances where an empty array should actually be an empty object.
  -- Specify an empty object by adding a single entry of "empty_object" to
  -- the table.
  return output:gsub('%["__empty_object__"%]', "{}")
end

---Decode a yaml node
---@param source string
---@return table
M.decode = function(source)
  return vim.json.decode(source)
end

return M
