return {
  name = "func_return_error",
  system_prompt = "my func system prompt",
  cmds = {
    function(self, actions, input)
      return "This works"
    end,
    function(self, actions, input)
      return { status = "error", data = "This will throw an error" }
    end,
    function(self, actions, input)
      return "This won't be reached"
    end,
  },
  handlers = {
    -- Should only be called once
    setup = function(self, agent)
      _G._test_order = (_G._test_order or "") .. "Setup"
      _G._test_setup = (_G._test_setup or "") .. "Setup"
    end,
    -- Should only be called once
    on_exit = function(self, agent)
      _G._test_order = (_G._test_order or "") .. "->Exit"
      _G._test_exit = (_G._test_exit or "") .. "Exited"
    end,
  },

  output = {
    ---@param self CodeCompanion.Agent
    ---@param cmd string
    ---@param stderr table
    ---@param stdout table
    error = function(self, agent, cmd, stderr, stdout)
      _G._test_order = (_G._test_order or "") .. "->Error"
      _G._test_output = "<error>" .. table.concat(stderr, " ") .. "</error>"
    end,

    success = function(self, agent, cmd, stderr, stdout)
      _G._test_order = (_G._test_order or "") .. "->Success"
      _G._test_output = "<error>" .. table.concat(stderr, " ") .. "</error>"
    end,
  },
}
