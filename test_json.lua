local jsonschema = require("jsonschema")
local schema = {
  type = "object",
  properties = {
    command = {
      type = "string",
      enum = { "query", "ls" },
      description = "Action to perform: 'query' for semantic search or 'ls' to list projects",
    },
    options = {
      type = "object",
      properties = {
        query = {
          type = "array",
          items = { type = "string" },
          description = "Query messages used for the search.",
        },
        count = {
          type = "integer",
          description = "Number of documents to retrieve, must be positive",
        },
        project_root = {
          type = "string",
          description = "Project path to search within (must be from 'ls' results)",
        },
      },
      required = { "query" },
      additionalProperties = false,
    },
  },
  required = { "command" },
  additionalProperties = false,
}

local args = { {
  command = "query",
  options = { query = { "hi" } },
}, { command = "ls" }, { command = "fhdsaif" } }

local validator = jsonschema.generate_validator(schema)
for _, arg in pairs(args) do
  local res, err = validator(arg, schema)
  vim.notify(vim.inspect({ args = arg, result = res, error = err }))
end
