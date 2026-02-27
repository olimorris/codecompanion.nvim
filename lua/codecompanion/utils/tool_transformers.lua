-- Utility functions to transform tool schemas between different formats

local M = {}

---Convert the OpenAI schema to Anthropic's schema
---REF: https://docs.anthropic.com/en/docs/build-with-claude/tool-use/overview#example-simple-tool-definition
---@param schema table
---@return table
M.to_anthropic = function(schema)
  local function_def = schema["function"]

  return {
    name = function_def.name,
    description = function_def.description,
    input_schema = {
      type = function_def.parameters.type,
      properties = function_def.parameters.properties,
      required = function_def.parameters.required,
    },
  }
end

---Recursively make all properties required and add null types
---@param obj table Object with properties field
local function make_all_properties_required(obj)
  if not obj.properties then
    return
  end

  local property_keys = {}
  for k, v in pairs(obj.properties) do
    table.insert(property_keys, k)

    if type(v.type) == "string" then
      v.type = { v.type, "null" }
    elseif type(v.type) == "table" and not vim.tbl_contains(v.type, "null") then
      table.insert(v.type, "null")
      table.sort(v.type)
    end

    -- Recurse for array items with object type
    if v.items and v.items.properties then
      v.items.additionalProperties = false
      make_all_properties_required(v.items)
    end

    -- Recurse for nested object properties
    if v.properties then
      v.additionalProperties = false
      make_all_properties_required(v)
    end
  end

  table.sort(property_keys)
  obj.required = property_keys
  obj.additionalProperties = false
end

---Enforce that the schema follows OpenAI's strictness rules
---@param schema table
---@return table
M.enforce_strictness = function(schema)
  schema["function"].parameters.strict = true
  make_all_properties_required(schema["function"].parameters)
  return schema
end

---Check if the schema is in the old OpenAI format
---@param schema table
---@return boolean
M.schema_is_legacy_format = function(schema)
  return schema["function"] ~= nil
end

---Convert the original OpenAI schema to the new OpenAI schema
---REF: https://platform.openai.com/docs/guides/function-calling#defining-functions
---@param schema table
---@param opts? {strict_mode: boolean}
---@return table
M.to_new_openai = function(schema, opts)
  -- The user must explicitly set strict_mode to true
  opts = vim.tbl_extend("force", { strict_mode = false }, opts or {})

  if opts.strict_mode and not schema["function"].parameters.strict then
    schema = M.enforce_strictness(schema)
  end

  local function_def = schema["function"]

  -- Use parameters.strict if set, otherwise use function.strict,
  -- otherwise use strict_mode option
  local strict_value = function_def.parameters.strict
  if strict_value == nil then
    strict_value = function_def.strict
  end
  if strict_value == nil then
    strict_value = opts.strict_mode
  end

  return {
    type = schema.type,
    name = function_def.name,
    description = function_def.description,
    parameters = {
      type = function_def.parameters.type,
      properties = function_def.parameters.properties,
      required = function_def.parameters.required,
      additionalProperties = function_def.parameters.additionalProperties or false,
    },
    strict = strict_value,
  }
end

---Transform the schema if it's in the old OpenAI format
---@param schema table
---@param opts? {strict_mode: boolean}
---@return table
M.transform_schema_if_needed = function(schema, opts)
  if M.schema_is_legacy_format(schema) then
    return M.to_new_openai(schema, opts)
  end
  return schema
end

return M
