local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
    end,
    post_once = child.stop,
  },
})

T["adapter cache"] = new_set()

T["adapter cache"]["updates when ChatAdapter event fires"] = function()
  child.lua([[
    local completion = require("codecompanion.providers.completion")
    local utils = require("codecompanion.utils")

    -- Create a test config with a conditional slash command
    local test_slash_commands = {
      test_cmd = {
        description = "Test command",
        enabled = function(opts)
          return opts.adapter and opts.adapter.name == "test_adapter"
        end,
      },
      opts = {},
    }

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)

    -- Fire ChatAdapter event with test adapter
    local adapter = { name = "test_adapter", type = "http" }
    utils.fire("ChatAdapter", { bufnr = bufnr, adapter = adapter })

    -- Get slash commands with our test config
    local slash_command_filter = require("codecompanion.interactions.chat.slash_commands.filter")
    local filtered = slash_command_filter.filter_enabled_slash_commands(test_slash_commands, { adapter = adapter })

    _G.test_result = filtered.test_cmd ~= nil

    vim.api.nvim_buf_delete(bufnr, { force = true })
  ]])

  h.eq(child.lua_get("_G.test_result"), true)
end

T["adapter cache"]["preserves adapter when ChatModel event without adapter fires"] = function()
  child.lua([[
    local utils = require("codecompanion.utils")

    local test_slash_commands = {
      test_cmd = {
        description = "Test command",
        enabled = function(opts)
          return opts.adapter and opts.adapter.type == "acp"
        end,
      },
      opts = {},
    }

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)

    -- Set an ACP adapter
    local adapter = { name = "claude_code", type = "acp" }
    utils.fire("ChatAdapter", { bufnr = bufnr, adapter = adapter })

    -- Fire ChatModel event without adapter field (simulating model selection)
    utils.fire("ChatModel", { bufnr = bufnr, model = "some-model" })

    -- Adapter should still be in cache, so filtering should still work
    local slash_command_filter = require("codecompanion.interactions.chat.slash_commands.filter")
    local filtered = slash_command_filter.filter_enabled_slash_commands(test_slash_commands, { adapter = adapter })

    _G.test_result = filtered.test_cmd ~= nil

    vim.api.nvim_buf_delete(bufnr, { force = true })
  ]])

  h.eq(child.lua_get("_G.test_result"), true)
end

T["adapter cache"]["clears when adapter explicitly set to nil"] = function()
  child.lua([[
    local utils = require("codecompanion.utils")

    local test_slash_commands = {
      test_cmd = {
        description = "Test command",
        enabled = function(opts)
          return opts.adapter and opts.adapter.name == "test_adapter"
        end,
      },
      always_enabled_cmd = {
        description = "Always enabled command",
        -- No enabled function, so always enabled
      },
      opts = {},
    }

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)

    -- Set an adapter - test_cmd should be enabled
    local adapter = { name = "test_adapter", type = "http" }
    utils.fire("ChatAdapter", { bufnr = bufnr, adapter = adapter })

    local slash_command_filter = require("codecompanion.interactions.chat.slash_commands.filter")
    local filtered_before = slash_command_filter.filter_enabled_slash_commands(test_slash_commands, { adapter = adapter })

    -- Explicitly clear it
    utils.fire("ChatAdapter", { bufnr = bufnr, adapter = nil })

    -- Refresh cache to pick up the cleared adapter
    slash_command_filter.refresh_cache()

    -- Filter with nil adapter - test_cmd should not be enabled, but always_enabled_cmd should be
    local filtered_after = slash_command_filter.filter_enabled_slash_commands(test_slash_commands, { adapter = nil })

    _G.test_cmd_before = filtered_before.test_cmd ~= nil
    _G.test_cmd_after = filtered_after.test_cmd == nil
    _G.always_enabled_before = filtered_before.always_enabled_cmd ~= nil
    _G.always_enabled_after = filtered_after.always_enabled_cmd ~= nil

    vim.api.nvim_buf_delete(bufnr, { force = true })
  ]])

  -- Before clearing: test_cmd should be enabled
  h.eq(child.lua_get("_G.test_cmd_before"), true)
  -- After clearing: test_cmd should be disabled
  h.eq(child.lua_get("_G.test_cmd_after"), true)
  -- always_enabled_cmd should be enabled in both cases
  h.eq(child.lua_get("_G.always_enabled_before"), true)
  h.eq(child.lua_get("_G.always_enabled_after"), true)
end

T["adapter cache"]["updates when switching from HTTP to ACP adapter"] = function()
  child.lua([[
    local utils = require("codecompanion.utils")

    -- Command that only works with ACP adapters
    local test_slash_commands = {
      acp_only_cmd = {
        description = "ACP only command",
        enabled = function(opts)
          return opts.adapter and opts.adapter.type == "acp"
        end,
      },
      opts = {},
    }

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)

    -- Start with HTTP adapter
    local http_adapter = { name = "copilot", type = "http" }
    utils.fire("ChatAdapter", { bufnr = bufnr, adapter = http_adapter })

    -- Command should not be available
    local slash_command_filter = require("codecompanion.interactions.chat.slash_commands.filter")
    local filtered_http = slash_command_filter.filter_enabled_slash_commands(
      test_slash_commands,
      { adapter = http_adapter }
    )

    -- Switch to ACP adapter
    local acp_adapter = { name = "claude_code", type = "acp" }
    utils.fire("ChatAdapter", { bufnr = bufnr, adapter = acp_adapter })

    -- Fire a ChatModel event without adapter (simulating model selection)
    utils.fire("ChatModel", { bufnr = bufnr, model = "default" })

    -- Command should now be available because we're using ACP adapter
    local filtered_acp = slash_command_filter.filter_enabled_slash_commands(
      test_slash_commands,
      { adapter = acp_adapter }
    )

    _G.http_result = filtered_http.acp_only_cmd == nil
    _G.acp_result = filtered_acp.acp_only_cmd ~= nil

    vim.api.nvim_buf_delete(bufnr, { force = true })
  ]])

  h.eq(child.lua_get("_G.http_result"), true)
  h.eq(child.lua_get("_G.acp_result"), true)
end

return T
