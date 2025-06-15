return {
  name = "func_approval",
  system_prompt = "my func approval system prompt",
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
    name = "func_approval",
  },
  handlers = {
    setup = function(self)
      _G._test_order = (_G._test_order or "") .. "Setup"
    end,
    on_exit = function(self)
      _G._test_order = (_G._test_order or "") .. "->Exit"
    end,
  },
  output = {
    prompt = function(self, agent)
      return "Run the func_approval tool?"
    end,
    success = function(self, cmd, output)
      _G._test_order = (_G._test_order or "") .. "->Success"
    end,
    rejected = function(self, agent, cmd)
      _G._test_order = (_G._test_order or "") .. "->Rejected"
    end,
  },
}
