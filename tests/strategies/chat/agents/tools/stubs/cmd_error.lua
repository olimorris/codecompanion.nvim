return {
  name = "cmd_error",
  system_prompt = function(schema)
    return "my cmd system prompt"
  end,
  cmds = {
    { "echofdsfds", "Hello World" },
  },
  handlers = {
    -- Should only be called once
    on_exit = function(self)
      _G._test_order = (_G._test_order or "") .. "->Exit"
      _G._test_exit = (_G._test_exit or "") .. "Exited"
    end,
  },
  output = {
    -- Should only be called once
    error = function(self, cmd, stderr, stdout)
      _G._test_output = (_G._test_output or "") .. "Error"
      _G._test_order = (_G._test_order or "") .. "Error"
    end,
  },
}
