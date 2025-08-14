return {
  name = "func_handlers_once",
  opts = {
    use_handlers_once = true,
  },
  system_prompt = "my func system prompt",
  cmds = {
    ---@return { status: string, data: any }
    function(self, args, input)
      local spacer = ""
      if _G._test_func then
        spacer = " "
      end
      _G._test_func = (_G._test_func or "") .. spacer .. args.data
      return { status = "success", data = args.data }
    end,
  },
  schema = {
    name = "func",
  },
  handlers = {
    setup = function(self)
      _G._test_order = (_G._test_order or "") .. "Setup"
      _G._test_setup = (_G._test_setup or "") .. "Setup"
    end,
    on_exit = function(self)
      _G._test_order = (_G._test_order or "") .. "->Exit"
      _G._test_exit = (_G._test_exit or "") .. "Exited"
    end,
  },
  output = {
    -- Should be called multiple times
    success = function(self, cmd, output)
      _G._test_order = (_G._test_order or "") .. "->Success"
      _G._test_output = (_G._test_output or "") .. "Ran with success"
      return "stdout is populated!"
    end,
  },
}
