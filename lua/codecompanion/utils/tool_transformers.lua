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

return M
