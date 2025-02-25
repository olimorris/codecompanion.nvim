return {
  name = "cmd_integrate",
  system_prompt = function(schema)
    return "my cmd system prompt"
  end,
  cmds = {
    { "sleep", "0.5" },
  },
  handlers = {
    -- Should only be called once
    setup = function(self)
      _G._test_order = (_G._test_order or "") .. "->Cmd[Setup]"
      _G._test_setup = (_G._test_setup or "") .. "Setup"
    end,
    -- Should only be called once
    on_exit = function(self)
      _G._test_order = (_G._test_order or "") .. "->Cmd[Exit]"
      _G._test_exit = (_G._test_exit or "") .. "Exited"
    end,
  },
  output = {
    -- Should only be called once
    success = function(self, cmd, output)
      _G._test_order = (_G._test_order or "") .. "->Cmd[Success]"
      _G._test_output = _G._test_output or {}
      table.insert(_G._test_output, output)
    end,
  },
}
