return {
  name = "mock_cmd_runner",
  system_prompt = "my func system prompt",
  cmds = {},
  handlers = {
    ---@param agent CodeCompanion.Agent The tool object
    setup = function(agent)
      local tool = agent.tool --[[@type CodeCompanion.Agent.Tool]]
      local args = tool.args

      local entry = { cmd = vim.split(args.cmds, " ") }
      if args.flag then
        entry.flag = args.flag
      end

      table.insert(tool.cmds, entry)
    end,

    -- Should only be called once
    on_exit = function(self)
      _G._test_order = (_G._test_order or "") .. "->Exit"
      _G._test_exit = (_G._test_exit or "") .. "Exited"
    end,
  },
  output = {
    -- Should only be called once
    error = function(self, cmd, stderr, stdout)
      _G._test_output = (_G._test_output or "") .. "Error"
      _G._test_order = (_G._test_order or "") .. "Error"
    end,
  },
}
