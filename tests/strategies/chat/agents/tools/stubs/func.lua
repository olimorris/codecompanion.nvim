return {
  name = "func",
  system_prompt = function(schema)
    return "my func system prompt"
  end,
  cmds = {
    function(self, actions, input)
      local spacer = ""
      if vim.g.codecompanion_test then
        spacer = " "
      end
      vim.g.codecompanion_test = (vim.g.codecompanion_test or "") .. spacer .. actions.data
    end,
  },
  handlers = {
    on_exit = function(self)
      vim.g.codecompanion_test_exit = (vim.g.codecompanion_test_exit or "") .. "Exited"
    end,
  },
  output = {
    success = function(self, cmd, output)
      vim.g.codecompanion_test_output = "Ran with success"
    end,
  },
}
