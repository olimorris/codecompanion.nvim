return {
  name = "weather",
  cmds = {
    ---@param self CodeCompanion.Agent.Tool The Tools object
    ---@param args table The action object
    ---@param input? any The output from the previous function call
    function(self, args, input)
      return {
        status = "success",
        data = "The weather in " .. args.location .. " is 75° " .. args.units,
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
            description = "The city and state, e.g. San Francisco, CA",
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
      return agent.chat:add_buf_message({
        role = "user",
        content = stdout[1],
      })
    end,
  },
}
