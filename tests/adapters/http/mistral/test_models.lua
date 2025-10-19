-- filepath: tests/adapters/http/mistral/test_models.lua
local h = require("tests.helpers")

local new_set = MiniTest.new_set

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

T["mistral.models"] = new_set()

T["mistral.models"]["choices() synchronous returns expected models"] = function()
  local result = child.lua([[
    local get_models = require("codecompanion.adapters.http.mistral.get_models")

    -- Mock Curl.get to return stub data
    local curl = require("plenary.curl")
    local body = vim.fn.readfile("tests/adapters/http/stubs/mistral_models.json")
    body = table.concat(body, "\n")

    curl.get = function(url, opts)
      if opts and type(opts.callback) == "function" then
        opts.callback({ status = 200, body = body })
      end
      return { status = 200, body = body }
    end

    -- Mock resolve() to return test adapter
    local http_adapters = require("codecompanion.adapters.http")
    http_adapters.resolve = function(self)
      return {
        env_replaced = {
          url = "https://api.mistral.ai",
          api_key = "test-key",
        },
        opts = {},
      }
    end

    -- Mock get_env_vars() to do nothing
    local adapters_utils = require("codecompanion.utils.adapters")
    adapters_utils.get_env_vars = function(adapter) end

    local adapter = { opts = {} }
    return get_models.choices(adapter)
  ]])

  -- This expected output is based on the logic in get_models.lua:
  -- 1. dedup_models prefers `-latest` names and keeps the model object whose id matches the preferred name.
  --    - `ministral-3b-2410` has alias `ministral-3b-latest`, so preferred is `...latest`. But no model with id `...latest` exists, so it's dropped.
  -- 2. The main loop then filters for `capabilities.completion_chat == true` and `deprecation == vim.NIL`.
  --    - `devstral-small-2505` is dropped due to deprecation.
  --    - `magistral-small-2506` is dropped due to deprecation.
  --    - `ministral-3b-2410` was already dropped by dedup. Even if it weren't, `completion_chat` is false.
  local expected = {
    ["mistral-medium-2505"] = {
      formatted_name = "mistral-medium-2505",
      opts = {
        has_vision = true,
        can_use_tools = true,
      },
    },
    ["mistral-large-latest"] = {
      formatted_name = "mistral-large-latest",
      opts = {
        has_vision = true,
        can_use_tools = true,
      },
    },
    ["ministral-8b-latest"] = {
      formatted_name = "ministral-8b-2410",
      opts = {
        has_vision = false,
        can_use_tools = true,
      },
    },
  }

  h.eq(result, expected)
end

return T
