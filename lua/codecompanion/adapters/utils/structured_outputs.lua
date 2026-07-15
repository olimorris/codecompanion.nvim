local M = {}

---Recursively enforce OpenAI strict-mode requirements on a JSON Schema
---@param node any
local function enforce_strict(node)
  if type(node) ~= "table" then
    return
  end

  if node.type == "object" or node.properties then
    node.additionalProperties = false

    if node.properties then
      local property_keys = {}
      for key, value in pairs(node.properties) do
        table.insert(property_keys, key)
        enforce_strict(value)
      end
      table.sort(property_keys)
      node.required = property_keys
    end
  end

  if node.items then
    enforce_strict(node.items)
  end

  for _, combinator in ipairs({ "anyOf", "oneOf", "allOf" }) do
    if type(node[combinator]) == "table" then
      for _, branch in ipairs(node[combinator]) do
        enforce_strict(branch)
      end
    end
  end
end

---@class CodeCompanion.StructuredOutput.Schema
---@field name string Identifier for the schema. Required for OpenAI / OpenAI Responses / OpenRouter; ignored by Anthropic / Gemini
---@field schema table The JSON Schema describing the response
---@field strict? boolean When true (default), OpenAI variants auto-enforce strict mode

---Convert a structured-output schema to the Anthropic Messages API body fragment
---Ref: https://platform.claude.com/docs/en/build-with-claude/structured-outputs#quick-start
---@param input CodeCompanion.StructuredOutput.Schema
---@return table
function M.to_anthropic(input)
  return {
    output_config = {
      format = {
        type = "json_schema",
        schema = vim.deepcopy(input.schema),
      },
    },
  }
end

---Strip fields that Gemini's restricted OpenAPI-subset schema rejects, e.g. `additionalProperties`
---@param node any
local function strip_unsupported_gemini_fields(node)
  if type(node) ~= "table" then
    return
  end
  node.additionalProperties = nil
  if node.properties then
    for _, value in pairs(node.properties) do
      strip_unsupported_gemini_fields(value)
    end
  end
  strip_unsupported_gemini_fields(node.items)
  for _, combinator in ipairs({ "anyOf", "oneOf", "allOf" }) do
    if type(node[combinator]) == "table" then
      for _, branch in ipairs(node[combinator]) do
        strip_unsupported_gemini_fields(branch)
      end
    end
  end
end

---Convert a structured-output schema to the Gemini generateContent body fragment
---Ref: https://ai.google.dev/gemini-api/docs/structured-output#rest
---@param input CodeCompanion.StructuredOutput.Schema
---@return table
function M.to_gemini(input)
  local schema = vim.deepcopy(input.schema)
  strip_unsupported_gemini_fields(schema)

  return {
    generationConfig = {
      responseMimeType = "application/json",
      responseSchema = schema,
    },
  }
end

---Convert a structured-output schema to the Gemini Interactions API body fragment
---Ref: https://ai.google.dev/gemini-api/docs/interactions-overview
---@param input CodeCompanion.StructuredOutput.Schema
---@return table
function M.to_gemini_interactions(input)
  local schema = vim.deepcopy(input.schema)
  strip_unsupported_gemini_fields(schema)

  return {
    response_format = {
      type = "text",
      mime_type = "application/json",
      schema = schema,
    },
  }
end

---Convert a structured-output schema to the Ollama generate API body fragment
---Ref: https://ollama.com/blog/structured-outputs
---@param input CodeCompanion.StructuredOutput.Schema
---@return table
function M.to_ollama(input)
  return {
    format = vim.deepcopy(input.schema),
  }
end

---Convert a structured-output schema to the OpenAI Chat Completions API body fragment
---Ref: https://developers.openai.com/cookbook/examples/structured_outputs_intro
---@param input CodeCompanion.StructuredOutput.Schema
---@return table
function M.to_openai(input)
  local schema = vim.deepcopy(input.schema)
  local strict = input.strict ~= false
  if strict then
    enforce_strict(schema)
  end

  return {
    response_format = {
      type = "json_schema",
      json_schema = {
        name = input.name,
        strict = strict,
        schema = schema,
      },
    },
  }
end

---Convert a structured-output schema to the OpenAI Responses API body fragment
---Ref: https://community.openai.com/t/responses-api-documentation-on-structured-outputs-is-lacking/1356632/5
---@param input CodeCompanion.StructuredOutput.Schema
---@return table
function M.to_openai_responses(input)
  local schema = vim.deepcopy(input.schema)
  local strict = input.strict ~= false
  if strict then
    enforce_strict(schema)
  end

  return {
    text = {
      format = {
        type = "json_schema",
        name = input.name,
        strict = strict,
        schema = schema,
      },
    },
  }
end

return M
