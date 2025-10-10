-- filepath: tests/adapters/http/copilot/test_models.lua
local h = require("tests.helpers")

local new_set = MiniTest.new_set
local expect = MiniTest.expect
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        config = require('tests.config')
        require('codecompanion').setup(config)
      ]])
    end,
    post_once = child.stop,
  },
})

T["copilot.models"] = new_set()

T["copilot.models"]["choices() synchronous returns expected models"] = function()
  local result = child.lua([[
    local get_models = require("codecompanion.adapters.http.copilot.get_models")

    -- Mock token.fetch()
    local token = require("codecompanion.adapters.http.copilot.token")
    token.fetch = function()
      return {
        copilot_token = "test-token",
        endpoints = { api = "https://api.githubcopilot.com" },
      }
    end

    -- Avoid filesystem side effects
    local adapters_utils = require("codecompanion.utils.adapters")
    adapters_utils.refresh_cache = function()
      return os.time() + 100
    end

    -- Mock Curl.get to trigger the scheduled callback with a stub response
    local curl = require("plenary.curl")
    local body = vim.json.encode({
      data = {
        {
          id = "model1",
          name = "Model One",
          vendor = "copilot",
          model_picker_enabled = true,
          capabilities = { type = "chat", supports = { streaming = true, tool_calls = true, vision = true } },
        },
        {
          id = "model2",
          name = "Model Two",
          vendor = "copilot",
          model_picker_enabled = true,
          capabilities = { type = "chat", supports = {} },
        },
        {
          id = "ignore1",
          name = "Ignore One",
          vendor = "copilot",
          model_picker_enabled = false,
          capabilities = { type = "chat", supports = { streaming = true } },
        },
        {
          id = "ignore2",
          name = "Ignore Two",
          vendor = "copilot",
          model_picker_enabled = true,
          capabilities = { type = "completion", supports = {} },
        },
      },
    })

    curl.get = function(url, opts)
      if opts and type(opts.callback) == "function" then
        -- opts.callback is wrapped with vim.schedule_wrap in the module
        opts.callback({ status = 200, body = body })
      end
      return { status = 200, body = body }
    end

    local adapter = { headers = {} }
    return get_models.choices(adapter, { async = false })
  ]])

  local expected = {
    model1 = {
      vendor = "copilot",
      endpoint = "completions",
      formatted_name = "Model One",
      opts = { can_stream = true, can_use_tools = true, has_vision = true },
    },
    model2 = {
      vendor = "copilot",
      endpoint = "completions",
      formatted_name = "Model Two",
      opts = {},
    },
  }

  h.eq(result, expected)
end

T["copilot.models"]["choices() async populates cache and returns later"] = function()
  local first, second = unpack(child.lua([[
    local get_models = require("codecompanion.adapters.http.copilot.get_models")

    -- Mock token.fetch()
    local token = require("codecompanion.adapters.http.copilot.token")
    token.fetch = function()
      return {
        copilot_token = "test-token",
        endpoints = { api = "https://api.githubcopilot.com" },
      }
    end

    -- Avoid filesystem side effects
    local adapters_utils = require("codecompanion.utils.adapters")
    adapters_utils.refresh_cache = function()
      return os.time() + 100
    end

    -- Mock Curl.get to trigger the scheduled callback with a stub response
    local curl = require("plenary.curl")
    local body = vim.json.encode({
      data = {
        {
          id = "model1",
          name = "Model One",
          vendor = "copilot",
          model_picker_enabled = true,
          capabilities = { type = "chat", supports = { streaming = true, tool_calls = true, vision = true } },
        },
        {
          id = "model2",
          name = "Model Two",
          vendor = "copilot",
          model_picker_enabled = true,
          capabilities = { type = "chat", supports = {} },
        },
      },
    })

    curl.get = function(url, opts)
      if opts and type(opts.callback) == "function" then
        opts.callback({ status = 200, body = body })
      end
      return { status = 200, body = body }
    end

    local adapter = { headers = {} }

    -- Start async fetch: should return nil initially (no cache yet)
    local first = get_models.choices(adapter, { async = true })

    -- Give scheduled callback a chance to run and fill cache
    vim.wait(50, function() return false end)

    -- Second call should return cached models
    local second = get_models.choices(adapter, { async = true })

    return { first, second }
  ]]))

  h.eq(vim.NIL, first)

  local expected = {
    model1 = {
      vendor = "copilot",
      endpoint = "completions",
      formatted_name = "Model One",
      opts = { can_stream = true, can_use_tools = true, has_vision = true },
    },
    model2 = {
      vendor = "copilot",
      endpoint = "completions",
      formatted_name = "Model Two",
      opts = {},
    },
  }

  h.eq(second, expected)
end

return T
