local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        _G.chat, _G.tools = h.setup_chat_buffer()
      ]])
    end,
    post_case = function()
      child.lua([[
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

T["ToolRegistry"] = new_set()

T["ToolRegistry"][":add"] = new_set()

T["ToolRegistry"][":add"]["adds a single tool to the registry"] = function()
  child.lua([[
    _G.chat.tool_registry:add("func")
  ]])

  local registry = child.lua_get([[_G.chat.tool_registry.in_use]])

  h.expect_tbl_contains("func", registry)
  h.expect_tbl_contains("<tool>func</tool>", child.lua_get([[_G.chat.tool_registry.schemas]]))
end

T["ToolRegistry"][":add"]["adds a group to the registry"] = function()
  child.lua([[
    _G.chat.tool_registry:add("senior_dev")
  ]])

  -- Group adds its tools to in_use
  local registry = child.lua_get([[_G.chat.tool_registry.in_use]])
  h.expect_tbl_contains("func", registry)
  h.expect_tbl_contains("cmd", registry)
end

T["ToolRegistry"][":add"]["renders tool in the chat buffer"] = function()
  child.lua([[
    _G.chat.tool_registry:add("func")
    _G.chat.context:render()
    _G.buf_lines = h.get_buf_lines(_G.chat.bufnr)
  ]])

  local lines = child.lua_get([[_G.buf_lines]])
  local content = table.concat(lines, "\n")

  h.expect_contains("func", content)
end

T["ToolRegistry"][":add_single_tool"] = new_set()

T["ToolRegistry"][":add_single_tool"]["adds a tool to the registry"] = function()
  child.lua([[
    _G.chat.tool_registry:add_single_tool("weather")
  ]])

  local registry = child.lua_get([[_G.chat.tool_registry.in_use]])
  h.expect_tbl_contains("weather", registry)
  h.expect_tbl_contains("<tool>weather</tool>", child.lua_get([[_G.chat.tool_registry.schemas]]))
end

T["ToolRegistry"][":add_single_tool"]["accepts config option"] = function()
  child.lua([[
    local config = require("tests.config")
    _G.chat.tool_registry:add_single_tool("weather", { config = config.interactions.chat.tools["weather"] })
  ]])

  local registry = child.lua_get([[_G.chat.tool_registry.in_use]])
  h.expect_tbl_contains("weather", registry)
end

T["ToolRegistry"][":add_single_tool"]["does not add duplicate tools"] = function()
  child.lua([[
    _G.chat.tool_registry:add_single_tool("func")
    _G.chat.tool_registry:add_single_tool("func")
    _G.tool_count = vim.tbl_count(_G.chat.tool_registry.in_use)
  ]])

  h.eq(1, child.lua_get([[_G.tool_count]]))
end

T["ToolRegistry"][":add_group"] = new_set()

T["ToolRegistry"][":add_group"]["adds all tools in a group"] = function()
  child.lua([[
    _G.chat.tool_registry:add_group("senior_dev")
  ]])

  local registry = child.lua_get([[_G.chat.tool_registry.in_use]])
  h.expect_tbl_contains("func", registry)
  h.expect_tbl_contains("cmd", registry)
end

T["ToolRegistry"][":add_group"]["adds group system prompt"] = function()
  child.lua([[
    _G.chat.tool_registry:add_group("tool_group")
    _G.has_system_prompt = false
    for _, msg in ipairs(_G.chat.messages) do
      if msg.content == "My tool group system prompt" then
        _G.has_system_prompt = true
        break
      end
    end
  ]])

  h.eq(true, child.lua_get([[_G.has_system_prompt]]))
end

T["ToolRegistry"][":loaded"] = new_set()

T["ToolRegistry"][":loaded"]["returns false when no tools loaded"] = function()
  h.eq(false, child.lua_get([[_G.chat.tool_registry:loaded()]]))
end

T["ToolRegistry"][":loaded"]["returns true when tools are loaded"] = function()
  child.lua([[
    _G.chat.tool_registry:add("func")
  ]])

  h.eq(true, child.lua_get([[_G.chat.tool_registry:loaded()]]))
end

T["ToolRegistry"][":clear"] = new_set()

T["ToolRegistry"][":clear"]["clears all tools from the registry"] = function()
  child.lua([[
    _G.chat.tool_registry:add("func")
    _G.chat.tool_registry:add("weather")
    _G.chat.tool_registry:clear()
  ]])

  h.eq(false, child.lua_get([[_G.chat.tool_registry:loaded()]]))
  h.eq({}, child.lua_get([[_G.chat.tool_registry.in_use]]))
  h.eq({}, child.lua_get([[_G.chat.tool_registry.schemas]]))
end

T["ToolRegistry"]["tools passed via args.tools"] = new_set()

T["ToolRegistry"]["tools passed via args.tools"]["are added to the registry"] = function()
  child.lua([[
    local config_module = require("codecompanion.config")
    local test_config = vim.deepcopy(require("tests.config"))
    config_module.setup(test_config)

    _G.chat_with_tools = require("codecompanion.interactions.chat").new({
      buffer_context = { bufnr = 1, filetype = "lua" },
      adapter = "test_adapter",
      tools = { "func", "weather" },
    })
  ]])

  local registry = child.lua_get([[_G.chat_with_tools.tool_registry.in_use]])
  h.expect_tbl_contains("func", registry)
  h.expect_tbl_contains("weather", registry)
end

T["ToolRegistry"]["tools passed via args.tools"]["are visible in the chat buffer"] = function()
  child.lua([[
    local config_module = require("codecompanion.config")
    local test_config = vim.deepcopy(require("tests.config"))
    config_module.setup(test_config)

    _G.chat_with_tools = require("codecompanion.interactions.chat").new({
      buffer_context = { bufnr = 1, filetype = "lua" },
      adapter = "test_adapter",
      tools = { "func" },
    })
    _G.buf_lines = h.get_buf_lines(_G.chat_with_tools.bufnr)
  ]])

  local lines = child.lua_get([[_G.buf_lines]])
  local content = table.concat(lines, "\n")

  h.expect_contains("func", content)
end

return T
