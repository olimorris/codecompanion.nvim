return {
  name = "cmd_queue",
  system_prompt = "my cmd system prompt",
  cmds = {
    vim.fn.has("win32") == 1 and { "ping", "-n", "1", "127.0.0.1" } or { "sleep", "0.5" },
  },
  handlers = {
    -- Should only be called once
    setup = function(self, meta)
      _G._test_order = (_G._test_order or "") .. "->Cmd[Setup]"
      _G._test_setup = (_G._test_setup or "") .. "Setup"
    end,
    -- Should only be called once
    on_exit = function(self, meta)
      _G._test_order = (_G._test_order or "") .. "->Cmd[Exit]"
      _G._test_exit = (_G._test_exit or "") .. "Exited"
    end,
  },
  output = {
    -- Should only be called once
    success = function(self, stdout, meta)
      _G._test_order = (_G._test_order or "") .. "->Cmd[Success]"
      _G._test_output = _G._test_output or {}
    end,
  },
}
