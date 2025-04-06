local Helpers = {}

Helpers = vim.tbl_extend("error", Helpers, require("tests.expectations"))

---Mock the plugin config
---@return table
local function mock_config()
  local config_module = require("codecompanion.config")
  config_module.setup = function(args)
    config_module.config = args or {}
  end
  config_module.can_send_code = function()
    return true
  end
  return config_module
end

---Set up the CodeCompanion plugin with test configuration
---@return nil
Helpers.setup_plugin = function()
  local test_config = require("tests.config")
  test_config.strategies.chat.adapter = "test_adapter"

  local codecompanion = require("codecompanion")
  codecompanion.setup(test_config)
  return codecompanion
end

---Mock the submit function of a chat to avoid actual API calls
---@param response string The mocked response content
---@param status? string The status to set (default: "success")
---@return function The original submit function for restoration
Helpers.mock_submit = function(response, status)
  local original_submit = require("codecompanion.strategies.chat").submit

  require("codecompanion.strategies.chat").submit = function(self)
    -- Mock submission instead of calling actual API
    self:add_buf_message({
      role = "llm",
      content = response or "This is a mocked response",
    })
    self.status = status or "success"
    self:done({ response or "Mocked response" })
    return true
  end

  return original_submit
end

---Restore the original submit function
---@param original function The original submit function to restore
---@return nil
Helpers.restore_submit = function(original)
  require("codecompanion.strategies.chat").submit = original
end

---Setup and mock a chat buffer
---@param config? table
---@param adapter? table
---@return CodeCompanion.Chat, CodeCompanion.Agent, CodeCompanion.Variables
Helpers.setup_chat_buffer = function(config, adapter)
  local test_config = vim.deepcopy(require("tests.config"))
  local config_module = mock_config()
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
  local agent = require("codecompanion.strategies.chat.agents").new({ bufnr = 1 })
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

  return chat, agent, vars
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
---@return nil
Helpers.teardown_chat_buffer = function()
  package.loaded["codecompanion.utils.foo"] = nil
  package.loaded["codecompanion.utils.bar"] = nil
  package.loaded["codecompanion.utils.bar_again"] = nil
end

---Get the lines of a buffer
---@param bufnr number
---@return table
Helpers.get_buf_lines = function(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
end

---Setup the inline buffer
---@param config table
---@return CodeCompanion.Inline
Helpers.setup_inline = function(config)
  local test_config = vim.deepcopy(require("tests.config"))
  local config_module = mock_config()
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
