return {
  name = "func",
  system_prompt = function(schema)
    return "my func system prompt"
  end,
  cmds = {
    ---@return { status: string, data: any }
    function(self, actions, input)
      local spacer = ""
      if vim.g.codecompanion_test then
        spacer = " "
      end
      vim.g.codecompanion_test = (vim.g.codecompanion_test or "") .. spacer .. actions.data
      return { status = "success", data = actions.data }
    end,
  },
  handlers = {
    -- Should only be called once
    setup = function(self)
      vim.g.codecompanion_test_setup = (vim.g.codecompanion_test_setup or "") .. "Setup"
    end,
    -- Should only be called once
    on_exit = function(self)
      vim.g.codecompanion_test_exit = (vim.g.codecompanion_test_exit or "") .. "Exited"
    end,
  },
  output = {
    -- Should be called multiple times
    success = function(self, cmd, output)
      vim.g.codecompanion_test_output = (vim.g.codecompanion_test_output or "") .. "Ran with success"
      return "stdout is populated!"
    end,
  },
}
