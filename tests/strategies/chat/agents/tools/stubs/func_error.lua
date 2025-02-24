return {
  name = "func_error",
  system_prompt = function(schema)
    return "my func system prompt"
  end,
  cmds = {
    function(self, actions, input)
      return error("Something went wrong")
    end,
  },
  output = {
    ---@param self CodeCompanion.Agent
    ---@param cmd string
    ---@param stderr table
    ---@param stdout table
    error = function(self, cmd, stderr, stdout)
      _G._test_output = "<error>" .. table.concat(stderr, " ") .. "</error>"
    end,
  },
}
