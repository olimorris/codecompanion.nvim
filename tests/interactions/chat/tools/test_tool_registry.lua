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

T["ToolRegistry"][":add"]["renders collapsed tool group without member tools"] = function()
  child.lua([[
    _G.chat.tool_registry:add("senior_dev")
    _G.chat.context:render()
    _G.buf_lines = h.get_buf_lines(_G.chat.bufnr)
  ]])

  local lines = child.lua_get([[_G.buf_lines]])
  local content = table.concat(lines, "\n")

  h.expect_contains("senior_dev", content)
  h.eq(nil, content:find("<tool>func</tool>", 1, true))
  h.eq(nil, content:find("<tool>cmd</tool>", 1, true))
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

T["ToolRegistry"][":add"]["hides tool context for ACP chats"] = function()
  child.lua([[
    _G.chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        roles = { user = "user", assistant = "assistant" },
        handlers = {
          form_messages = function()
            return {}
          end,
        },
      },
    })
    _G.chat.tool_registry:add("func")
    _G.chat.context:render()
    _G.buf_lines = h.get_buf_lines(_G.chat.bufnr)
  ]])

  local lines = child.lua_get([[_G.buf_lines]])
  local content = table.concat(lines, "\n")

  h.expect_tbl_contains("func", child.lua_get([[_G.chat.tool_registry.in_use]]))
  h.eq(nil, content:find("func", 1, true))
end

T["ToolRegistry"][":add"]["hides tool group context for ACP chats"] = function()
  child.lua([[
    _G.chat = h.setup_chat_buffer({}, {
      name = "test_acp",
      config = {
        name = "test_acp",
        type = "acp",
        roles = { user = "user", assistant = "assistant" },
        handlers = {
          form_messages = function()
            return {}
          end,
        },
      },
    })
    _G.chat.tool_registry:add("senior_dev")
    _G.chat.context:render()
    _G.buf_lines = h.get_buf_lines(_G.chat.bufnr)
  ]])

  local lines = child.lua_get([[_G.buf_lines]])
  local content = table.concat(lines, "\n")

  h.expect_tbl_contains("func", child.lua_get([[_G.chat.tool_registry.in_use]]))
  h.expect_tbl_contains("cmd", child.lua_get([[_G.chat.tool_registry.in_use]]))
  h.eq(nil, content:find("senior_dev", 1, true))
  h.eq(nil, content:find("func", 1, true))
  h.eq(nil, content:find("cmd", 1, true))
end

T["ToolRegistry"][":add"]["updates tool context visibility when switching to ACP"] = function()
  child.lua([[
    _G.chat.tool_registry:add("senior_dev")
    _G.http_visible = _G.chat.context_items[1].opts.visible

    _G.chat.adapter = { name = "test_acp", type = "acp" }
    _G.chat.tool_registry:update_context_visibility()
    _G.acp_visible = _G.chat.context_items[1].opts.visible

    _G.chat.adapter = { name = "test_adapter", type = "http" }
    _G.chat.tool_registry:update_context_visibility()
    _G.http_again_visible = _G.chat.context_items[1].opts.visible
  ]])

  h.eq(true, child.lua_get([[_G.http_visible]]))
  h.eq(false, child.lua_get([[_G.acp_visible]]))
  h.eq(true, child.lua_get([[_G.http_again_visible]]))
end

T["ToolRegistry"][":add"]["returns nil for unknown name"] = function()
  local result = child.lua_get([[_G.chat.tool_registry:add("nonexistent_tool_xyz")]])

  h.eq(vim.NIL, result)
  h.eq({}, child.lua_get([[_G.chat.tool_registry.in_use]]))
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

T["ToolRegistry"][":add_single_tool"]["does not add duplicate adapter tools"] = function()
  child.lua([[
    _G.chat.tool_registry:add_single_tool("adapter_tool")
    _G.chat.tool_registry:add_single_tool("adapter_tool")
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

T["ToolRegistry"][":add_group"]["does not add duplicate groups"] = function()
  child.lua([[
    _G.chat.tool_registry:add_group("tool_group")
    _G.chat.tool_registry:add_group("tool_group")
    _G.system_prompt_count = 0
    for _, msg in ipairs(_G.chat.messages) do
      if msg.context and msg.context.id == "<group>tool_group</group>" then
        _G.system_prompt_count = _G.system_prompt_count + 1
      end
    end
  ]])

  h.eq(1, child.lua_get([[_G.system_prompt_count]]), "Group system prompt should only be added once")
  h.eq(2, child.lua_get([[vim.tbl_count(_G.chat.tool_registry.in_use)]]), "Should still have 2 tools")
end

T["ToolRegistry"][":add_group"]["skips tools missing from config"] = function()
  child.lua([[
    _G.chat.tool_registry:add_group("senior_dev", {
      config = {
        groups = {
          ["senior_dev"] = {
            description = "Tool Group",
            tools = { "func", "nonexistent_tool" },
          },
        },
        ["func"] = require("tests.config").interactions.chat.tools["func"],
      },
    })
  ]])

  local registry = child.lua_get([[_G.chat.tool_registry.in_use]])
  h.expect_tbl_contains("func", registry)
  h.eq(1, child.lua_get([[vim.tbl_count(_G.chat.tool_registry.in_use)]]))
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

T["ToolRegistry"]["add_tool_system_prompt"] = new_set()

T["ToolRegistry"]["add_tool_system_prompt"]["receives the added tool in its argument"] = function()
  child.lua([[
    _G.chat2, _G.tools2 = h.setup_chat_buffer({
      interactions = {
        chat = {
          tools = {
            opts = {
              system_prompt = {
                enabled = true,
                replace_main_system_prompt = false,
                prompt = function(args)
                  _G.prompt_tools_arg = vim.deepcopy(args.tools)
                  return "tool system prompt"
                end,
              },
            },
          },
        },
      },
    })
    _G.chat2.tool_registry:add_single_tool("func")
  ]])

  local prompt_tools_arg = child.lua_get([[_G.prompt_tools_arg]])
  h.expect_tbl_contains("func", prompt_tools_arg)
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
  h.eq({}, child.lua_get([[_G.chat.tool_registry.groups]]))
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

T["ToolRegistry"][":remove_group"] = new_set()

T["ToolRegistry"][":remove_group"]["removes group tools, context items and messages"] = function()
  child.lua([[
    _G.chat.tool_registry:add_group("remove_group")
  ]])

  -- Verify tools were added
  h.expect_tbl_contains("func", child.lua_get([[_G.chat.tool_registry.in_use]]))
  h.expect_tbl_contains("weather", child.lua_get([[_G.chat.tool_registry.in_use]]))
  h.eq(true, child.lua_get([[_G.chat.tool_registry.groups["remove_group"] ~= nil]]))

  child.lua([[
    _G.chat.tool_registry:remove_group("remove_group")
  ]])

  -- in_use, schemas and groups should be empty
  h.eq({}, child.lua_get([[_G.chat.tool_registry.in_use]]))
  h.eq({}, child.lua_get([[_G.chat.tool_registry.schemas]]))
  h.eq({}, child.lua_get([[_G.chat.tool_registry.groups]]))

  -- Context items referencing the group should be removed
  h.eq({}, child.lua_get([[_G.chat.context_items]]))

  -- The group's system prompt message should be removed
  child.lua([[
    _G.has_removed_prompt = false
    for _, msg in ipairs(_G.chat.messages) do
      if msg.content == "System prompt to be removed" then
        _G.has_removed_prompt = true
        break
      end
    end
  ]])

  h.eq(false, child.lua_get([[_G.has_removed_prompt]]))
end

T["ToolRegistry"][":add_group"]["ignore_system_prompt removes the default system prompt"] = function()
  child.lua([[
    -- Verify the default system prompt exists before adding the group
    _G.has_default_before = false
    for _, msg in ipairs(_G.chat.messages) do
      if msg._meta and msg._meta.tag == "system_prompt_from_config" then
        _G.has_default_before = true
        break
      end
    end

    _G.chat.tool_registry:add_group("ignore_sys_prompt_group")

    _G.has_default_after = false
    _G.has_group_prompt = false
    for _, msg in ipairs(_G.chat.messages) do
      if msg._meta and msg._meta.tag == "system_prompt_from_config" then
        _G.has_default_after = true
      end
      if msg.content == "Custom agent system prompt" then
        _G.has_group_prompt = true
      end
    end
  ]])

  h.eq(true, child.lua_get([[_G.has_default_before]]), "Default system prompt should exist initially")
  h.eq(false, child.lua_get([[_G.has_default_after]]), "Default system prompt should be removed")
  h.eq(true, child.lua_get([[_G.has_group_prompt]]), "Group system prompt should be added")
  h.eq(true, child.lua_get([[_G.chat.tool_registry.flags.ignore_system_prompt]]))
end

T["ToolRegistry"][":add_group"]["ignore_tool_system_prompt sets the flag"] = function()
  child.lua([[
    _G.chat.tool_registry:add_group("ignore_tool_sys_prompt_group")
  ]])

  h.eq(true, child.lua_get([[_G.chat.tool_registry.flags.ignore_tool_system_prompt]]))
end

T["ToolRegistry"][":add_group"]["ignore_system_prompt is restored on remove_group"] = function()
  child.lua([[
    _G.chat.tool_registry:add_group("ignore_sys_prompt_group")

    _G.has_default_after_add = false
    for _, msg in ipairs(_G.chat.messages) do
      if msg._meta and msg._meta.tag == "system_prompt_from_config" then
        _G.has_default_after_add = true
        break
      end
    end
  ]])

  -- Verify the default system prompt is removed
  h.eq(false, child.lua_get([[_G.has_default_after_add]]))

  child.lua([[
    _G.chat.tool_registry:remove_group("ignore_sys_prompt_group")

    _G.has_default_after_remove = false
    for _, msg in ipairs(_G.chat.messages) do
      if msg._meta and msg._meta.tag == "system_prompt_from_config" then
        _G.has_default_after_remove = true
        break
      end
    end
  ]])

  -- Default system prompt should be restored
  h.eq(
    true,
    child.lua_get([[_G.has_default_after_remove]]),
    "Default system prompt should be restored after removing the group"
  )

  -- Flag should be cleared
  h.eq(vim.NIL, child.lua_get([[_G.chat.tool_registry.flags.ignore_system_prompt]]))
end

T["ToolRegistry"][":add_group"]["ignore_tool_system_prompt is restored on remove_group"] = function()
  child.lua([[
    _G.chat.tool_registry:add_group("ignore_tool_sys_prompt_group")
  ]])

  h.eq(true, child.lua_get([[_G.chat.tool_registry.flags.ignore_tool_system_prompt]]))

  child.lua([[
    _G.chat.tool_registry:remove_group("ignore_tool_sys_prompt_group")
  ]])

  h.eq(vim.NIL, child.lua_get([[_G.chat.tool_registry.flags.ignore_tool_system_prompt]]))
end

T["ToolRegistry"]["ctx"] = new_set()

T["ToolRegistry"]["ctx"]["is stored on the registry"] = function()
  local ctx = child.lua_get([[_G.chat.tool_registry.ctx]])

  h.not_eq(vim.NIL, ctx)
  h.not_eq(nil, ctx)
end

T["ToolRegistry"]["ctx"]["contains system prompt context fields"] = function()
  local ctx = child.lua_get([[_G.chat.tool_registry.ctx]])

  -- Static fields are directly accessible
  h.not_eq(nil, ctx.nvim_version)
  -- Dynamic fields (os, adapter) use metatables and are not serialized by child.lua_get
  -- but nvim_version is a static field that should be present
  local expected_version =
    child.lua_get([[vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch]])
  h.eq(expected_version, ctx.nvim_version)
end

T["ToolRegistry"]["ctx"]["is passed to tool system prompt function"] = function()
  child.lua([[
    local config_module = require("codecompanion.config")
    local test_config = vim.deepcopy(require("tests.config"))
    test_config.interactions.chat.tools.opts.system_prompt = {
      enabled = true,
      replace_main_system_prompt = false,
      prompt = function(args)
        _G.captured_args = args
        return "tool system prompt"
      end,
    }
    config_module.setup(test_config)

    _G.chat2, _ = require("tests.helpers").setup_chat_buffer(test_config)
    _G.chat2.tool_registry:add_single_tool("func")
  ]])

  local captured = child.lua_get([[_G.captured_args]])
  h.not_eq(vim.NIL, captured)
  h.not_eq(nil, captured.ctx)
  h.not_eq(nil, captured.tools)
end

T["ToolRegistry"]["ctx"]["ctx passed to tool system prompt has correct fields"] = function()
  child.lua([[
    local config_module = require("codecompanion.config")
    local test_config = vim.deepcopy(require("tests.config"))
    test_config.interactions.chat.tools.opts.system_prompt = {
      enabled = true,
      replace_main_system_prompt = false,
      prompt = function(args)
        _G.captured_ctx = args.ctx
        return "tool system prompt"
      end,
    }
    config_module.setup(test_config)

    _G.chat3, _ = require("tests.helpers").setup_chat_buffer(test_config)
    _G.chat3.tool_registry:add_single_tool("func")
  ]])

  local nvim_version =
    child.lua_get([[vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch]])
  local captured_ctx = child.lua_get([[_G.captured_ctx]])
  h.eq(nvim_version, captured_ctx.nvim_version)
end

T["ToolRegistry"]["ctx"]["tools list is passed alongside ctx"] = function()
  child.lua([[
    local config_module = require("codecompanion.config")
    local test_config = vim.deepcopy(require("tests.config"))
    test_config.interactions.chat.tools.opts.system_prompt = {
      enabled = true,
      replace_main_system_prompt = false,
      prompt = function(args)
        _G.captured_tools = args.tools
        return "tool system prompt"
      end,
    }
    config_module.setup(test_config)

    _G.chat4, _ = require("tests.helpers").setup_chat_buffer(test_config)
    _G.chat4.tool_registry:add_single_tool("func")
    -- Add a second tool so that prompt is called again with func already in in_use
    _G.chat4.tool_registry:add_single_tool("weather")
  ]])

  local captured_tools = child.lua_get([[_G.captured_tools]])
  h.not_eq(vim.NIL, captured_tools)
  -- After adding weather, prompt is called with func already in in_use
  h.expect_tbl_contains("func", captured_tools)
end

return T
