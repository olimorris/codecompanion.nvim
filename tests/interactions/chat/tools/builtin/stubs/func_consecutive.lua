local log = require("codecompanion.utils.log")
return {
  name = "func_consecutive",
  system_prompt = "my func system prompt",
  cmds = {
    function(self, args, opts)
      log:debug("FIRST ACTION")
      local input = opts.input
      return { status = "success", data = (input and (input .. " ") or "") .. args.data }
    end,
    function(self, args, opts)
      log:debug("SECOND ACTION")
      local input = opts.input and opts.input.data or nil
      local output = (input or "") .. " " .. args.data
      _G._test_func = output
      return { status = "success", data = output }
    end,
  },
  handlers = {
    -- Should only be called once
    setup = function(self, meta)
      _G._test_order = (_G._test_order or "") .. "Setup"
      _G._test_setup = (_G._test_setup or "") .. "Setup"
    end,
    -- Should only be called once
    on_exit = function(self, meta)
      _G._test_order = (_G._test_order or "") .. "->Exit"
      _G._test_exit = (_G._test_exit or "") .. "Exited"
    end,
  },

  output = {
    -- Should be called multiple times
    success = function(self, stdout, meta)
      _G._test_order = (_G._test_order or "") .. "->Success"
      _G._test_output = (_G._test_output or "") .. "Ran with success"
      return "stdout is populated!"
    end,
  },
}
