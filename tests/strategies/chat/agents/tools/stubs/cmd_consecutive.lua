return {
  name = "cmd consecutive",
  system_prompt = function(schema)
    return "my cmd system prompt"
  end,
  cmds = {
    { "echo", "Hello World" },
    { "echo", "Hello CodeCompanion" },
  },
  handlers = {
    -- Should only be called once
    setup = function(self)
      _G._test_order = (_G._test_order or "") .. "Setup"
      _G._test_setup = (_G._test_setup or "") .. "Setup"
      _G._test_output = {}
    end,
    -- Should only be called once
    on_exit = function(self)
      _G._test_order = (_G._test_order or "") .. "->Exit"
      _G._test_exit = (_G._test_exit or "") .. "Exited"
    end,
  },
  output = {
    -- Should only be called once
    success = function(self, cmd, output)
      _G._test_order = (_G._test_order or "") .. "->Success"
      table.insert(_G._test_output, output)
    end,
  },
}
