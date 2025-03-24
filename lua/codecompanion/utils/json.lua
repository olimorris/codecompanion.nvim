local M = {}

---@param data any
---@return string
M.encode = function(data)
  return vim.json.encode(data)
end

---Decode a yaml node
---@param source string
---@return table
M.decode = function(source)
  return vim.json.decode(source)
end

return M
