local M = {}

local islist = vim.islist or vim.tbl_islist

---@param data any
---@return string
M.encode = function(data)
  local dt = type(data)
  if data == nil then
    return "null"
  elseif dt == "number" then
    if data % 1 == 0 then
      return string.format("%d", data)
    else
      return string.format("%.1f", data)
    end
  elseif dt == "boolean" then
    return string.format("%s", data)
  elseif dt == "string" then
    if data == "yes" or data == "no" or data == "true" or data == "false" or data == "on" or data == "off" then
      return string.format('"%s"', data)
    else
      return data
    end
  elseif dt == "table" then
    local lines = {}
    if islist(data) then
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

---@param lines string[]
---@return string
local function fold_lines(lines)
  local folded = ""
  local previous
  for _, line in ipairs(lines) do
    if line == "" then
      folded = folded .. "\n"
    elseif previous == nil or previous == "" then
      folded = folded .. line
    elseif line:match("^%s") or previous:match("^%s") then
      folded = folded .. "\n" .. line
    else
      folded = folded .. " " .. line
    end
    previous = line
  end
  return folded
end

---Decode a literal (`|`) or folded (`>`) block scalar
---@param text string
---@return string
local function decode_block_scalar(text)
  local header, body = text:match("^([^\n]*)\n?(.*)$")
  local lines = vim.split(body, "\n", { plain = true })

  local indent
  for _, line in ipairs(lines) do
    if line:match("%S") then
      local width = #line:match("^ *")
      indent = indent and math.min(indent, width) or width
    end
  end
  lines = vim.tbl_map(function(line)
    return line:match("%S") and line:sub((indent or 0) + 1) or ""
  end, lines)

  local value = header:match("^>") and fold_lines(lines) or table.concat(lines, "\n")
  -- Tree-sitter leaves trailing blank lines out of the node, so `+` can only keep the final newline
  if header:match("^[>|][%d+]*%-") or value == "" then
    return value
  end
  return value .. "\n"
end

---Decode a yaml node
---@param source string
---@param node TSNode
---@return any
local function decode(source, node)
  local ok, nt = pcall(function()
    return node:type()
  end)
  if not ok then
    return {}
  end

  if nt == "stream" or nt == "document" or nt == "block_node" or nt == "flow_node" or nt == "plain_scalar" then
    for child in node:iter_children() do
      if child:named() then
        return decode(source, child)
      end
    end
  elseif nt == "block_mapping" then
    local result = {}
    for child in node:iter_children() do
      if child:type() == "comment" then
        goto continue
      end
      assert(child:type() == "block_mapping_pair")
      local key = decode(source, child:named_child(0))
      if not key then
        error("Could not decode map key")
      end
      result[key] = decode(source, child:named_child(1))
      ::continue::
    end
    -- Provide a way to get the TSNode for a map
    return setmetatable(result, {
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
  elseif nt == "block_sequence_item" then
    for child in node:iter_children() do
      if child:named() then
        return decode(source, child)
      end
    end
    return nil
  elseif nt == "string_scalar" then
    return vim.treesitter.get_node_text(node, source)
  elseif nt == "single_quote_scalar" or nt == "double_quote_scalar" then
    local text = vim.treesitter.get_node_text(node, source)
    return text:sub(2, text:len() - 1)
  elseif nt == "block_scalar" then
    return decode_block_scalar(vim.treesitter.get_node_text(node, source))
  elseif nt == "integer_scalar" or nt == "float_scalar" then
    return tonumber(vim.treesitter.get_node_text(node, source))
  elseif nt == "boolean_scalar" then
    local text = vim.treesitter.get_node_text(node, source)
    if text == "true" then
      return true
    elseif text == "false" then
      return false
    else
      error("Invalid boolean scalar")
    end
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
