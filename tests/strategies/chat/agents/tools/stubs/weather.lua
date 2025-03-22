return {
  name = "weather",
  cmds = {
    function(city)
      return {
        status = "success",
        data = "The weather in " .. city .. " is 75°F",
      }
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "get_weather",
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
    ---@param agent CodeCompanion.Agent
    ---@param cmd table The command that was executed
    ---@param stdout table
    success = function(agent, cmd, stdout)
      print("Weather: " .. stdout[1])
    end,
  },
}
