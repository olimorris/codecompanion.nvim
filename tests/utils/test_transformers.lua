local h = require("tests.helpers")
local transform = require("codecompanion.utils.tool_transformers")
local new_set = MiniTest.new_set
T = new_set()

T["Transformers"] = new_set({})

T["Transformers"]["can transform to Anthropic schema"] = function()
  local openai = vim.fn.readfile("tests/adapters/http/stubs/transformers/openai.txt")
  openai = vim.json.decode(table.concat(openai, "\n"))

  local anthropic = vim.fn.readfile("tests/adapters/http/stubs/transformers/anthropic.txt")
  anthropic = vim.json.decode(table.concat(anthropic, "\n"))

  local output = transform.to_anthropic(openai)

  h.eq(output, anthropic)
end

local schema = {
  ["function"] = {
    description = "Search for files in the workspace by glob pattern. This only returns the paths of matching files. Use this tool when you know the exact filename pattern of the files you're searching for. Glob patterns match from the root of the workspace folder. Examples:\n- **/*.{js,ts} to match all js/ts files in the workspace.\n- src/** to match all files under the top-level src folder.\n- **/foo/**/*.js to match all js files under any foo folder in the workspace.",
    name = "file_search",
    parameters = {
      properties = {
        max_results = {
          description = "The maximum number of results to return. Do not use this unless necessary, it can slow things down. By default, only some matches are returned. If you use this and don't see what you're looking for, you can try again with a more specific query or a larger max_results.",
          type = "number",
        },
        query = {
          description = "Search for files with names or paths matching this glob pattern.",
          type = "string",
        },
      },
      required = { "query" },
      type = "object",
    },
  },
  type = "function",
}

T["Transformers"]["can enforce strictness"] = function()
  local expected = {
    ["function"] = {
      description = "Search for files in the workspace by glob pattern. This only returns the paths of matching files. Use this tool when you know the exact filename pattern of the files you're searching for. Glob patterns match from the root of the workspace folder. Examples:\n- **/*.{js,ts} to match all js/ts files in the workspace.\n- src/** to match all files under the top-level src folder.\n- **/foo/**/*.js to match all js files under any foo folder in the workspace.",
      name = "file_search",
      parameters = {
        properties = {
          max_results = {
            description = "The maximum number of results to return. Do not use this unless necessary, it can slow things down. By default, only some matches are returned. If you use this and don't see what you're looking for, you can try again with a more specific query or a larger max_results.",
            type = { "number", "null" },
          },
          query = {
            description = "Search for files with names or paths matching this glob pattern.",
            type = { "string", "null" },
          },
        },
        required = { "max_results", "query" },
        additionalProperties = false,
        type = "object",
        strict = true,
      },
    },
    type = "function",
  }

  h.eq(expected, transform.enforce_strictness(vim.deepcopy(schema)))
end

T["Transformers"]["can enforce strictness with a partially strict schema"] = function()
  local expected = {
    ["function"] = {
      description = "Search for files in the workspace by glob pattern. This only returns the paths of matching files. Use this tool when you know the exact filename pattern of the files you're searching for. Glob patterns match from the root of the workspace folder. Examples:\n- **/*.{js,ts} to match all js/ts files in the workspace.\n- src/** to match all files under the top-level src folder.\n- **/foo/**/*.js to match all js files under any foo folder in the workspace.",
      name = "file_search",
      parameters = {
        properties = {
          max_results = {
            description = "The maximum number of results to return. Do not use this unless necessary, it can slow things down. By default, only some matches are returned. If you use this and don't see what you're looking for, you can try again with a more specific query or a larger max_results.",
            type = { "number", "null" },
          },
          query = {
            description = "Search for files with names or paths matching this glob pattern.",
            type = { "string", "null" },
          },
        },
        required = { "max_results", "query" },
        additionalProperties = false,
        type = "object",
        strict = true,
      },
    },
    type = "function",
  }

  local updated_schema = vim.deepcopy(schema)
  updated_schema["function"].parameters.strict = true
  h.eq(expected, transform.enforce_strictness(updated_schema))

  -- Prevent multiple null types
  updated_schema = vim.deepcopy(schema)
  updated_schema["function"].parameters.properties.max_results.type = { "number", "null" }
  h.eq(expected, transform.enforce_strictness(updated_schema))
end

T["Transformers"]["can enforce strictness with nested objects in arrays"] = function()
  local nested_schema = {
    type = "function",
    ["function"] = {
      name = "insert_edit_into_file",
      description = "Edit a file",
      parameters = {
        type = "object",
        properties = {
          filepath = {
            type = "string",
            description = "The file path",
          },
          edits = {
            type = "array",
            description = "Array of edit operations",
            items = {
              type = "object",
              properties = {
                oldText = {
                  type = "string",
                  description = "Text to find",
                },
                newText = {
                  type = "string",
                  description = "Text to replace with",
                },
                replaceAll = {
                  type = "boolean",
                  default = false,
                  description = "Replace all occurrences",
                },
              },
              required = { "oldText", "newText" },
            },
          },
        },
        required = { "filepath", "edits" },
      },
    },
  }

  local result = transform.enforce_strictness(vim.deepcopy(nested_schema))

  -- Check that top-level properties have null types
  h.eq({ "string", "null" }, result["function"].parameters.properties.filepath.type)
  h.eq({ "array", "null" }, result["function"].parameters.properties.edits.type)

  -- Check that nested items have all properties in required array (including previously optional ones)
  h.eq({ "newText", "oldText", "replaceAll" }, result["function"].parameters.properties.edits.items.required)

  -- Check that nested properties have null types
  h.eq({ "string", "null" }, result["function"].parameters.properties.edits.items.properties.oldText.type)
  h.eq({ "string", "null" }, result["function"].parameters.properties.edits.items.properties.newText.type)
  h.eq({ "boolean", "null" }, result["function"].parameters.properties.edits.items.properties.replaceAll.type)

  -- Check that strict mode is enabled
  h.eq(true, result["function"].parameters.strict)

  -- Check that additionalProperties is set to false on all objects
  h.eq(false, result["function"].parameters.additionalProperties)
  h.eq(false, result["function"].parameters.properties.edits.items.additionalProperties)
end

T["Transformers"]["transform_schema_if_needed uses strict_mode when schema has no strict field"] = function()
  local schema_without_strict = {
    type = "function",
    ["function"] = {
      name = "test_tool",
      description = "A test tool",
      -- No strict field
      parameters = {
        type = "object",
        properties = {
          query = {
            type = "string",
            description = "Query parameter",
          },
        },
        required = { "query" },
        additionalProperties = false,
      },
    },
  }

  -- With strict_mode = false, strict should be false/nil
  local result1 = transform.transform_schema_if_needed(vim.deepcopy(schema_without_strict), { strict_mode = false })
  h.eq(false, result1.strict)
  h.eq("string", result1.parameters.properties.query.type) -- No null type

  -- With strict_mode = true, strict should be true and strictness enforced
  local result2 = transform.transform_schema_if_needed(vim.deepcopy(schema_without_strict), { strict_mode = true })
  h.eq(true, result2.strict)
  h.eq({ "string", "null" }, result2.parameters.properties.query.type) -- Has null type
  h.eq({ "query" }, result2.parameters.required) -- All properties required
end

T["Transformers"]["enforces additionalProperties false on deeply nested MCP schemas"] = function()
  -- Schema modeled after @modelcontextprotocol/server-memory create_entities
  local mcp_schema = {
    type = "function",
    ["function"] = {
      name = "knowledge_graph_memory__create_entities",
      description = "Create multiple new entities in the knowledge graph",
      parameters = {
        type = "object",
        properties = {
          entities = {
            type = "array",
            description = "An array of entities to create",
            items = {
              type = "object",
              properties = {
                name = {
                  type = "string",
                  description = "The name of the entity",
                },
                entityType = {
                  type = "string",
                  description = "The type of the entity",
                },
                observations = {
                  type = "array",
                  description = "An array of observation contents",
                  items = { type = "string" },
                },
              },
              required = { "name", "entityType", "observations" },
            },
          },
        },
        required = { "entities" },
      },
    },
  }

  local result = transform.enforce_strictness(vim.deepcopy(mcp_schema))

  -- Top-level additionalProperties
  h.eq(false, result["function"].parameters.additionalProperties)

  -- Nested items object must have additionalProperties = false
  h.eq(false, result["function"].parameters.properties.entities.items.additionalProperties)

  -- Nested items properties should have null types
  h.eq({ "string", "null" }, result["function"].parameters.properties.entities.items.properties.name.type)
  h.eq({ "string", "null" }, result["function"].parameters.properties.entities.items.properties.entityType.type)
  h.eq({ "array", "null" }, result["function"].parameters.properties.entities.items.properties.observations.type)

  -- All nested properties should be required
  h.eq({ "entityType", "name", "observations" }, result["function"].parameters.properties.entities.items.required)
end

T["Transformers"]["enforces additionalProperties false via transform_schema_if_needed with strict_mode"] = function()
  local mcp_schema = {
    type = "function",
    ["function"] = {
      name = "test_nested_tool",
      description = "A tool with nested objects",
      parameters = {
        type = "object",
        properties = {
          items = {
            type = "array",
            items = {
              type = "object",
              properties = {
                key = { type = "string" },
                value = { type = "string" },
              },
              required = { "key", "value" },
            },
          },
        },
        required = { "items" },
      },
    },
  }

  -- With strict_mode = true, nested objects should get additionalProperties = false
  local result = transform.transform_schema_if_needed(vim.deepcopy(mcp_schema), { strict_mode = true })
  h.eq(false, result.parameters.additionalProperties)
  h.eq(false, result.parameters.properties.items.items.additionalProperties)
  h.eq(true, result.strict)

  -- With strict_mode = false, no additionalProperties should be added to nested objects
  local result2 = transform.transform_schema_if_needed(vim.deepcopy(mcp_schema), { strict_mode = false })
  h.eq(nil, result2.parameters.properties.items.items.additionalProperties)
end

T["Transformers"]["respects function.strict = false even when strict_mode is true"] = function()
  -- Schema like mcphub's use_mcp_tool that opts out of strict mode
  local opt_out_schema = {
    type = "function",
    ["function"] = {
      name = "use_mcp_tool",
      description = "calls tools on MCP servers.",
      parameters = {
        type = "object",
        properties = {
          server_name = {
            description = "Name of the server",
            type = "string",
          },
          tool_name = {
            description = "Name of the tool",
            type = "string",
          },
          tool_input = {
            description = "Input object for the tool call",
            type = "object",
            additionalProperties = false,
          },
        },
        required = { "server_name", "tool_name", "tool_input" },
        additionalProperties = false,
      },
      strict = false, -- Explicitly opt out of strict mode
    },
  }

  -- With strict_mode = true but function.strict = false, strictness should NOT be enforced
  local result = transform.transform_schema_if_needed(vim.deepcopy(opt_out_schema), { strict_mode = true })
  h.eq(false, result.strict)
  -- Properties should NOT have null types added (strictness not enforced)
  h.eq("string", result.parameters.properties.server_name.type)
  h.eq("string", result.parameters.properties.tool_name.type)
  h.eq("object", result.parameters.properties.tool_input.type)
end
return T
