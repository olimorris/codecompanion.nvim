return {
  name = "func_queue",
  system_prompt = "my func system prompt",
  cmds = {
    ---@return { status: string, data: any }
    function(self, actions, input)
      local spacer = ""
      if _G._test_func then
        spacer = " "
      end
      _G._test_func = (_G._test_func or "") .. spacer .. actions.data
      return { status = "success", data = actions.data }
    end,
  },
  handlers = {
    -- Should only be called once
    setup = function(self, tools)
      _G._test_order = (_G._test_order or "") .. "Func[Setup]"
      _G._test_setup = (_G._test_setup or "") .. "Setup"
    end,
    -- Should only be called once
    on_exit = function(self, tools)
      _G._test_order = (_G._test_order or "") .. "->Func[Exit]"
      _G._test_exit = (_G._test_exit or "") .. "Exited"
    end,
  },
  output = {
    -- Should be called multiple times
    success = function(self, tools, cmd, output)
      _G._test_order = (_G._test_order or "") .. "->Func[Success]"
      _G._test_output = (_G._test_output or "") .. "Ran with success"
      return "stdout is populated!"
    end,
  },
}
