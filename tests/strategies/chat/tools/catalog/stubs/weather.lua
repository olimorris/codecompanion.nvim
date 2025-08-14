local log = require("codecompanion.utils.log")
return {
  name = "weather",
  cmds = {
    ---@param self CodeCompanion.Tools.Tool The Tools object
    ---@param args table The action object
    ---@param input? any The output from the previous function call
    function(self, args, input)
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
      name = "weather",
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
        required = {
          "location",
          "units",
        },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  output = {
    ---@param self CodeCompanion.Tools.Tool
    ---@param tools CodeCompanion.Tools
    ---@param cmd table The command that was executed
    ---@param stdout table
    success = function(self, tools, cmd, stdout)
      local output = stdout[#stdout]
      tools.chat:add_tool_output(self, "Ran the weather tool " .. output, output)
    end,
  },
}
