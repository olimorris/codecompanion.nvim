return {
  name = "cmd",
  system_prompt = function(schema)
    return "my cmd system prompt"
  end,
  cmds = {
    { "echo", "Hello World" },
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
    end,
  },
}
