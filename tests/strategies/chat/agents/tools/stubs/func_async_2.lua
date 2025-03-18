return {
  name = "func_async_2",
  system_prompt = "my func system prompt",
  cmds = {
    function(self, actions, input, cb)
      local spacer = ""
      if _G._test_func then
        spacer = " "
      end
      _G._test_func = (_G._test_func or "") .. spacer .. actions.data
      assert(type(cb) == "function")
      coroutine.wrap(function()
        local co = coroutine.running()
        vim.defer_fn(function()
          coroutine.resume(co)
        end, 500)
        coroutine.yield()
        cb({ status = "success", data = actions.data })
      end)()
    end,
  },
  handlers = {
    -- Should only be called once
    setup = function(self)
      _G._test_order = (_G._test_order or "") .. "->AsyncFunc2[Setup]"
      _G._test_setup = (_G._test_setup or "") .. "Setup"
    end,
    -- Should only be called once
    on_exit = function(self)
      _G._test_order = (_G._test_order or "") .. "->AsyncFunc2[Exit]"
      _G._test_exit = (_G._test_exit or "") .. "Exited"
    end,
  },
  output = {
    -- Should be called multiple times
    success = function(self, cmd, output)
      _G._test_order = (_G._test_order or "") .. "->AsyncFunc2[Success]"
      _G._test_output = (_G._test_output or "") .. "Ran with success"
      return "stdout is populated!"
    end,
  },
}
