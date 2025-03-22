return {
  name = "mock_cmd_runner",
  system_prompt = "my func system prompt",
  cmds = {},
  handlers = {
    ---@param agent CodeCompanion.Agent The tool object
    setup = function(agent)
      local tool = agent.tool --[[@type CodeCompanion.Agent.Tool]]
      local action = tool.request.action
      local actions = vim.isarray(action) and action or { action }

      for _, act in ipairs(actions) do
        local entry = { cmd = vim.split(act.command, " ") }
        if act.flag then
          entry.flag = act.flag
        end
        table.insert(tool.cmds, entry)
      end
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
