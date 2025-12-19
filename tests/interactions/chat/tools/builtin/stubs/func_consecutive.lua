local log = require("codecompanion.utils.log")
return {
  name = "func_consecutive",
  system_prompt = "my func system prompt",
  cmds = {
    ---In production, we should be outputting as { status: string, data: any }
    function(self, args, input)
      log:debug("FIRST ACTION")
      return (input and (input .. " ") or "") .. args.data
    end,
    function(self, args, input)
      log:debug("SECOND ACTION")
      local output = input .. " " .. args.data
      _G._test_func = output
      return output
    end,
  },
  handlers = {
    -- Should only be called once
    setup = function(self, tools)
      _G._test_order = (_G._test_order or "") .. "Setup"
      _G._test_setup = (_G._test_setup or "") .. "Setup"
    end,
    -- Should only be called once
    on_exit = function(self, tools)
      _G._test_order = (_G._test_order or "") .. "->Exit"
      _G._test_exit = (_G._test_exit or "") .. "Exited"
    end,
  },

  output = {
    -- Should be called multiple times
    success = function(self, tools, cmd, output)
      _G._test_order = (_G._test_order or "") .. "->Success"
      _G._test_output = (_G._test_output or "") .. "Ran with success"
      return "stdout is populated!"
    end,
  },
}
