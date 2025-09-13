local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")
        h.setup_plugin()
        package.loaded["codecompanion.config"] = require("tests.config")
      ]])
    end,
    post_case = child.stop,
  },
})

T["Goose ACP Adapter"] = new_set()

T["Goose ACP Adapter"]["can resolve goose adapter"] = function()
  local result = child.lua([[
    local adapter = require("codecompanion.adapters").resolve("goose")
    return {
      name = adapter.name,
      formatted_name = adapter.formatted_name,
      type = adapter.type,
      resolved = require("codecompanion.adapters").resolved(adapter)
    }
  ]])

  h.eq({
    name = "goose",
    formatted_name = "Goose",
    type = "acp",
    resolved = true,
  }, result)
end

T["Goose ACP Adapter"]["has correct default configuration"] = function()
  local result = child.lua([[
    local adapter = require("codecompanion.adapters").resolve("goose")
    return {
      roles = adapter.roles,
      opts = adapter.opts,
      commands = adapter.commands,
      defaults = adapter.defaults,
    }
  ]])

  h.eq({
    roles = { llm = "assistant", user = "user" },
    opts = { vision = true },
    commands = { default = { "goose", "acp" }, selected = { "goose", "acp" } },
    defaults = { mcpServers = {}, timeout = 20000 },
  }, result)
end

T["Goose ACP Adapter"]["has correct parameters"] = function()
  local result = child.lua([[
    local adapter = require("codecompanion.adapters").resolve("goose")
    return adapter.parameters
  ]])

  h.eq({
    protocolVersion = 1,
    clientCapabilities = {
      fs = { readTextFile = true, writeTextFile = true },
    },
    clientInfo = {
      name = "CodeCompanion.nvim",
      version = "1.0.0",
    },
  }, result)
end

T["Goose ACP Adapter"]["handlers setup returns true"] = function()
  local result = child.lua([[
    local adapter = require("codecompanion.adapters").resolve("goose")
    return adapter.handlers.setup(adapter)
  ]])

  h.eq(true, result)
end

T["Goose ACP Adapter"]["form_messages handler works correctly"] = function()
  local result = child.lua([[
    local adapter = require("codecompanion.adapters").resolve("goose")
    local messages = {
      { role = "user", content = "Hello", _meta = { sent = false } },
      { role = "assistant", content = "Hi there!", _meta = { sent = true } }
    }
    local capabilities = { promptCapabilities = {} }
    local formed = adapter.handlers.form_messages(adapter, messages, capabilities)

    -- Basic check that messages are returned (only unsent user messages should be returned)
    return {
      count = #formed,
      first_type = formed[1] and formed[1].type or "text"
    }
  ]])

  h.eq({
    count = 1,
    first_type = "text",
  }, result)
end

return T
