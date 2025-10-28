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

return T
