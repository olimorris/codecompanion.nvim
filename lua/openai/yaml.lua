local M = {}

---@param data any
---@return string
M.encode = function(data)
  local dt = type(data)
  if data == nil then
    return "null"
  elseif dt == "number" then
    return string.format("%d", data)
  elseif dt == "boolean" then
    return string.format("%s", data)
  elseif dt == "string" then
    if
      data == "yes"
      or data == "no"
      or data == "true"
      or data == "false"
      or data == "on"
      or data == "off"
    then
      return string.format('"%s"', data)
    else
      return data
    end
  elseif dt == "table" then
    local lines = {}
    if vim.tbl_islist(data) then
      if vim.tbl_isempty(data) then
        return "[]"
      else
        for _, v in ipairs(data) do
          table.insert(lines, string.format("- %s", M.encode(v)))
        end
      end
    else
      if vim.tbl_isempty(data) then
        return "{}"
      else
        for k, v in pairs(data) do
          table.insert(lines, string.format("%s: %s", k, M.encode(v)))
        end
      end
    end
    return table.concat(lines, "\n")
  else
    error(string.format("Cannot encode type '%s' to yaml", dt))
  end
end

local function decode(source, node)
  local nt = node:type()
  if
    nt == "stream"
    or nt == "document"
    or nt == "block_node"
    or nt == "flow_node"
    or nt == "plain_scalar"
  then
    if node:child_count() > 1 then
      error(string.format("Node %s has more than 1 child", nt))
    end
    return decode(source, node:child(0))
  elseif nt == "block_sequence_item" then
    if node:child_count() ~= 2 then
      error("block_sequence_item should have exactly 2 children")
    end
    -- First child is anonymous "-"
    return decode(source, node:child(1))
  elseif nt == "block_mapping" then
    local ret = {}
    for child in node:iter_children() do
      assert(child:type() == "block_mapping_pair")
      local key = decode(source, child:named_child(0))
      if not key then
        error("Could not decode map key")
      end
      ret[key] = decode(source, child:named_child(1))
    end
    -- Provide a way to get the TSNode for a map
    return setmetatable(ret, {
      __index = {
        __ts_node = node,
      },
    })
  elseif nt == "flow_sequence" or nt == "block_sequence" then
    local ret = {}
    for child in node:iter_children() do
      if child:named() then
        table.insert(ret, decode(source, child))
      end
    end
    return ret
  elseif nt == "string_scalar" then
    return vim.treesitter.get_node_text(node, source)
  elseif nt == "single_quote_scalar" or nt == "double_quote_scalar" then
    local text = vim.treesitter.get_node_text(node, source)
    return text:sub(2, text:len() - 1)
  elseif nt == "integer_scalar" or nt == "float_scalar" then
    return tonumber(vim.treesitter.get_node_text(node, source))
  elseif nt == "null_scalar" then
    return nil
  elseif nt == "ERROR" then
    -- TODO should probably annotate this and pass it up somehow
    return nil
  else
    error(string.format("Unknown yaml node type '%s'", nt))
  end
end

---@param source string|integer
---@param node TSNode
---@return any
M.decode_node = function(source, node)
  return decode(source, node)
end

---@param str string
---@return any
M.decode = function(str)
  local lang_tree = vim.treesitter.get_string_parser(str, "yaml", { injections = { yaml = "" } })
  local root = lang_tree:parse()[1]:root()
  return decode(str, root)
end

return M
