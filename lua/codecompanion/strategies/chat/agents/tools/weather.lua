return {
  name = "weather",
  cmds = {
    ---@param self CodeCompanion.Agent.Tool The Tools object
    ---@param args table The action object
    ---@param input? any The output from the previous function call
    function(self, args, input)
      return {
        status = "success",
        data = "**Tool Output**: The weather in " .. args.location .. " is 15° " .. args.units,
      }
    end,
  },
  system_prompt = "Use the weather tool to get the current weather for a single location.",
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
    ---@param self CodeCompanion.Agent.Tool
    ---@param agent CodeCompanion.Agent
    ---@param cmd table The command that was executed
    ---@param stdout table
    success = function(self, agent, cmd, stdout)
      local output = stdout[#stdout]
      agent.chat:add_tool_output(self, "Ran the weather tool " .. output, output)
    end,
  },
}
