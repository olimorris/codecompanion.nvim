local Helpers = {}

Helpers.expect = MiniTest.expect --[[@type function]]
Helpers.eq = MiniTest.expect.equality --[[@type function]]
Helpers.not_eq = MiniTest.expect.no_equality --[[@type function]]
Helpers.expect_starts_with = MiniTest.new_expectation( --[[@type function]]
  -- Expectation subject
  "string starts with",
  -- Predicate
  function(pattern, str)
    return str:find("^" .. pattern) ~= nil
  end,
  -- Fail context
  function(pattern, str)
    return string.format("Expected string to start with: %s\nObserved string: %s", vim.inspect(pattern), str)
  end
)

local function make_config()
  -- Overwrite the config with the test config
  local config_module = require("codecompanion.config")
  config_module.setup = function(args)
    config_module.config = args or {}
  end
  config_module.can_send_code = function()
    return true
  end
  return config_module
end

Helpers.setup_chat_buffer = function(config, adapter)
  local test_config = vim.deepcopy(require("tests.config"))
  local config_module = make_config()
  config_module.setup(vim.tbl_deep_extend("force", test_config, config or {}))

  -- Extend the adapters
  if adapter then
    config_module.adapters[adapter.name] = adapter.config
  end

  local chat = require("codecompanion.strategies.chat").new({
    context = { bufnr = 1, filetype = "lua" },
    adapter = adapter and adapter.name or "test_adapter",
  })
  chat.vars = {
    foo = {
      callback = "spec.codecompanion.strategies.chat.variables.foo",
      description = "foo",
    },
  }
  local tools = require("codecompanion.strategies.chat.tools").new({ bufnr = 1 })
  local vars = require("codecompanion.strategies.chat.variables").new()

  package.loaded["codecompanion.utils.foo"] = {
    name = "foo",
    cmds = {
      function(self, actions, input)
        self.chat:add_buf_message({ role = "user", content = "This is from the foo tool" })
        return { status = "success", msg = "" }
      end,
    },
    system_prompt = function()
      return "my foo system prompt"
    end,
  }
  package.loaded["codecompanion.utils.bar"] = {
    name = "bar",
    cmds = {
      function(self, actions, input)
        self.chat:add_buf_message({ role = "user", content = "This is from the bar tool" })
        return { status = "success", msg = "" }
      end,
    },
    system_prompt = function()
      return "my bar system prompt"
    end,
  }
  package.loaded["codecompanion.utils.bar_again"] = {
    system_prompt = function()
      return "baz"
    end,
  }

  return chat, tools, vars
end

---Mock the sending of a chat buffer to an LLM
---@param chat CodeCompanion.Chat
---@param message string
---@param callback? function
---@return nil
Helpers.send_to_llm = function(chat, message, callback)
  message = message or "Hello there"
  chat:submit()
  chat:add_buf_message({ role = "llm", content = message })
  chat.status = "success"
  if callback then
    callback()
  end
  chat:done({ message })
end

---Clean down the chat buffer if required
Helpers.teardown_chat_buffer = function()
  -- package.loaded["codecompanion.utils.foo"] = nil
  -- package.loaded["codecompanion.utils.bar"] = nil
  -- package.loaded["codecompanion.utils.bar_again"] = nil
end

---Get the lines of a buffer
Helpers.get_buf_lines = function(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
end

---Setup the inline buffer
Helpers.setup_inline = function(config)
  local test_config = vim.deepcopy(require("tests.config"))
  local config_module = make_config()
  config_module.setup(vim.tbl_deep_extend("force", test_config, config or {}))

  return require("codecompanion.strategies.inline").new({
    context = {
      winnr = 0,
      bufnr = 0,
      filetype = "lua",
      start_line = 1,
      end_line = 1,
      start_col = 0,
      end_col = 0,
    },
  })
end

return Helpers
