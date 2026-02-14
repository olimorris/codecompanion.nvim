local log = require("codecompanion.utils.log")
return {
  name = "weather_with_default",
  cmds = {
    ---@param self CodeCompanion.Tools.Tool The Tools object
    ---@param args table The action object
    ---@param input? any The output from the previous function call
    function(self, args, input)
      args = vim.tbl_deep_extend("force", { location = "London, UK", units = "celsius" }, args or {})
      _G.weather_output = "The weather in " .. args.location .. " is 15° " .. args.units
      return {
        status = "success",
        data = _G.weather_output,
      }
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "weather_with_default",
      description = "Retrieves current weather for the given location.",
      parameters = {
        type = "object",
        properties = {
          location = {
            type = "string",
            description = "City and country e.g. Bogotá, Colombia",
          },
          units = {
            type = "string",
            enum = {
              "celsius",
              "fahrenheit",
            },
            description = "Units the temperature will be returned in.",
          },
        },
        required = {},
        additionalProperties = false,
      },
      strict = false,
    },
  },
  output = {
    ---@param self CodeCompanion.Tools.Tool
    ---@param stdout table
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    success = function(self, stdout, meta)
      local output = stdout[#stdout]
      meta.tools.chat:add_tool_output(self, "Ran the weather tool " .. output, output)
    end,
  },
}
