return {
  name = "func_error",
  system_prompt = "my func system prompt",
  cmds = {
    function(self, actions, input)
      return error("Something went wrong")
    end,
  },
  handlers = {
    -- Should only be called once
    setup = function(self)
      _G._test_order = (_G._test_order or "") .. "Setup"
      _G._test_setup = (_G._test_setup or "") .. "Setup"
    end,
    -- Should only be called once
    on_exit = function(self)
      _G._test_order = (_G._test_order or "") .. "->Exit"
      _G._test_exit = (_G._test_exit or "") .. "Exited"
    end,
  },

  output = {
    ---@param self CodeCompanion.Agent
    ---@param cmd string
    ---@param stderr table
    ---@param stdout table
    error = function(self, cmd, stderr, stdout)
      _G._test_order = (_G._test_order or "") .. "->Error"
      _G._test_output = "<error>" .. table.concat(stderr, " ") .. "</error>"
    end,
  },
}
