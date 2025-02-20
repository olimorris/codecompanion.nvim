return {
  name = "func_consecutive",
  system_prompt = function(schema)
    return "my func system prompt"
  end,
  cmds = {
    function(self, actions, input)
      return (input and (input .. " ") or "") .. actions.data
    end,
    function(self, actions, input)
      local output = input .. " " .. actions.data
      vim.g.codecompanion_test = output
      return output
    end,
  },
}
