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
    error = function(self, cmd, error)
      vim.g.codecompanion_test_output = "<error>" .. error .. "</error>"
    end,
  },
}
