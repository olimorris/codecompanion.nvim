require("tests.log")
local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local chat, agent

T["Agent"] = new_set({
  hooks = {
    pre_case = function()
      chat, agent = h.setup_chat_buffer()
    end,
    post_case = function()
      h.teardown_chat_buffer()
      vim.g.codecompanion_test = nil
      vim.g.codecompanion_test_exit = nil
      vim.g.codecompanion_test_output = nil
    end,
  },
})

T["Agent"]["functions"] = new_set()

T["Agent"]["functions"]["can run functions"] = function()
  h.eq(vim.g.codecompanion_test, nil)
  agent:execute(
    chat,
    [[<tools>
  <tool name="func">
    <action type="type1"><data>Data 1</data></action>
    <action type="type2"><data>Data 2</data></action>
  </tool>
</tools>]]
  )

  -- Test that the function was called
  h.eq("Data 1 Data 2", vim.g.codecompanion_test)
end

T["Agent"]["functions"]["calls output.success when running functions"] = function()
  h.eq(vim.g.codecompanion_test_output, nil)
  agent:execute(
    chat,
    [[<tools>
  <tool name="func">
    <action type="type1"><data>Data 1</data></action>
    <action type="type2"><data>Data 2</data></action>
  </tool>
</tools>]]
  )

  -- Test `output.success` handler
  h.eq("Ran with success", vim.g.codecompanion_test_output)
end

T["Agent"]["functions"]["can call on_exit only once for functions"] = function()
  h.eq(vim.g.codecompanion_test_exit, nil)
  agent:execute(
    chat,
    [[<tools>
  <tool name="func">
    <action type="type1"><data>Data 1</data></action>
    <action type="type2"><data>Data 2</data></action>
  </tool>
</tools>]]
  )

  -- Test that the on_exit handler was called, once
  h.eq(vim.g.codecompanion_test_exit, "Exited")
end

T["Agent"]["functions"]["can run consecutive functions and pass input"] = function()
  h.eq(vim.g.codecompanion_test, nil)
  agent:execute(
    chat,
    [[<tools>
  <tool name="func_consecutive">
    <action type="type1"><data>Data 1</data></action>
  </tool>
</tools>]]
  )

  -- Test that the function was called
  h.eq("Data 1 Data 1", vim.g.codecompanion_test)
end

T["Agent"]["functions"]["can run multiple, consecutive functions"] = function()
  h.eq(vim.g.codecompanion_test, nil)
  agent:execute(
    chat,
    [[<tools>
  <tool name="func_consecutive">
    <action type="type1"><data>Data 1</data></action>
    <action type="type2"><data>Data 2</data></action>
  </tool>
</tools>]]
  )

  -- Test that the function was called, overwriting the global variable
  h.eq("Data 1 Data 2 Data 1 Data 2", vim.g.codecompanion_test)
end

T["Agent"]["functions"]["can handle errors in functions"] = function()
  agent:execute(
    chat,
    [[<tools>
  <tool name="func_error">
    <action type="type1"><data>Data 1</data></action>
  </tool>
</tools>]]
  )

  -- Test that the `output.error` handler was called
  h.eq("<error>Something went wrong</error>", vim.g.codecompanion_test_output)
end

T["Agent"]["functions"]["can populate stderr in functions"] = function()
  -- Prevent stderr from being cleared out
  function agent:reset()
    return nil
  end

  agent:execute(
    chat,
    [[<tools>
  <tool name="func_error">
    <action type="type1"><data>Data 1</data></action>
  </tool>
</tools>]]
  )

  -- Test that stderr is updated on the agent
  h.eq({ "Something went wrong" }, agent.stderr)
end

return T
