return {
  name = "func_consecutive",
  system_prompt = function(schema)
    return "my func system prompt"
  end,
  cmds = {
    ---In production, we should be outputting as { status: string, data: any }
    function(self, actions, input)
      return (input and (input .. " ") or "") .. actions.data
    end,
    function(self, actions, input)
      local output = input .. " " .. actions.data
      _G._test_func = output
      return output
    end,
  },
}
