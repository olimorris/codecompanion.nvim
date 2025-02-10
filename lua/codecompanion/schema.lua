---@class CodeCompanion.Schema
---@field type "string"|"number"|"integer"|"boolean"|"enum"|"list"|"map"
---@field mapping string
---@field order nil|integer
---@field optional nil|boolean
---@field choices nil|table
---@field desc string
---@field validate? fun(value: any): boolean, nil|string

local M = {}

local islist = vim.islist or vim.tbl_islist

---Return the default values for a schema
---@param schema CodeCompanion.Schema
---@param defaults? table Any default values to use (will override schema defaults)
M.get_default = function(schema, defaults)
  local ret = {}
  for k, v in pairs(schema) do
    if type(v.condition) == "function" and not v.condition(schema) then
      goto continue
    end

    if not vim.startswith(k, "_") then
      if defaults and defaults[k] ~= nil then
        ret[k] = defaults[k]
      else
        ret[k] = v.default
      end
    end
    ::continue::
  end
  return ret
end

---@param schema CodeCompanion.Schema
---@param value any
---@param adapter? CodeCompanion.Adapter
---@return boolean
---@return nil|string
local function validate_type(schema, value, adapter)
  local ptype = schema.type or "string"
  if value == nil then
    return schema.optional
  elseif ptype == "enum" then
    local choices = schema.choices
    if type(choices) == "function" then
      if adapter then
        choices = choices(adapter)
      else
        choices = choices()
      end
    end
    local valid = vim.tbl_contains(choices, value)
    if not valid and choices then
      return valid, string.format("must be one of %s", table.concat(choices, ", "))
    else
      return valid
    end
  elseif ptype == "list" then
    -- TODO validate subtype
    return type(value) == "table" and islist(value)
  elseif ptype == "map" then
    local valid = type(value) == "table" and (vim.tbl_isempty(value) or not islist(value))
    -- TODO validate subtype and subtype_key
    if valid then
      -- Hack to make sure empty dicts get serialized properly
      setmetatable(value, vim._empty_dict_mt)
    end
    return valid
  elseif ptype == "number" then
    return type(value) == "number"
  elseif ptype == "integer" then
    return type(value) == "number" and math.floor(value) == value
  elseif ptype == "boolean" then
    return type(value) == "boolean"
  elseif ptype == "string" then
    return true
  else
    error(string.format("Unknown param type '%s'", ptype))
  end
end

---@param schema CodeCompanion.Schema
---@param value any
---@param adapter? CodeCompanion.Adapter
---@return boolean
---@return nil|string
local function validate_field(schema, value, adapter)
  local valid, err = validate_type(schema, value, adapter)
  if not valid then
    return valid, err
  end
  if schema.validate and value ~= nil then
    return schema.validate(value)
  end
  return true
end

---@param schema CodeCompanion.Schema
---@param values table
---@param adapter? CodeCompanion.Adapter
---@return nil|table<string, string>
M.validate = function(schema, values, adapter)
  local errors = {}
  for k, v in pairs(schema) do
    local valid, err = validate_field(v, values[k], adapter)
    if not valid then
      errors[k] = err or string.format("Not a valid %s", v.type)
    end
  end
  if not vim.tbl_isempty(errors) then
    return errors
  end
end

---@param schema CodeCompanion.Schema
---@return string[]
M.get_ordered_keys = function(schema)
  for k, v in pairs(schema) do
    if type(v.condition) == "function" and not v.condition(schema) then
      schema[k] = nil
    end
  end

  local keys = vim.tbl_keys(schema)

  -- Sort the params by required, then if they have no value, then by name
  table.sort(keys, function(a, b)
    local aparam = schema[a]
    local bparam = schema[b]
    if aparam.order then
      if not bparam.order then
        return true
      elseif aparam.order ~= bparam.order then
        return aparam.order < bparam.order
      end
    elseif bparam.order then
      return false
    end
    if (aparam.optional == true) ~= (bparam.optional == true) then
      return bparam.optional
    end
    return a < b
  end)
  return keys
end

return M
