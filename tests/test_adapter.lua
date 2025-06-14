local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        utils = require("codecompanion.utils.adapters")

        _G.test_adapter = {
          name = "TestAdapter",
          url = "https://api.testgenai.com/v1/chat/completions",
          headers = {
            content_type = "application/json",
          },
          parameters = {
            stream = true,
          },
          schema = {
            model = {
              order = 1,
              mapping = "parameters.data",
              type = "enum",
              desc = "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
              default = "gpt-4-0125-preview",
              choices = {
                "gpt-4-1106-preview",
                "gpt-4",
                "gpt-3.5-turbo-1106",
                "gpt-3.5-turbo",
              },
            },
            temperature = {
              order = 2,
              mapping = "parameters.options",
              type = "number",
              optional = true,
              default = 1,
              desc = "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
              validate = function(n)
                return n >= 0 and n <= 2, "Must be between 0 and 2"
              end,
            },
            top_p = {
              order = 3,
              mapping = "parameters.options",
              type = "number",
              optional = true,
              default = 1,
              desc = "An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.",
              validate = function(n)
                return n >= 0 and n <= 1, "Must be between 0 and 1"
              end,
            },
          },
        }

        _G.chat_buffer_settings = {
          frequency_penalty = 0,
          model = "gpt-4-0125-preview",
          presence_penalty = 0,
          temperature = 1,
          top_p = 1,
          stop = nil,
          max_tokens = nil,
          logit_bias = nil,
          user = nil,
        }

        _G.test_adapter2 = {
          name = "TestAdapter2",
          url = "https://api.oli.ai/v1/chat/${model}",
          env = {
            home = "HOME",
            model = "schema.model.default",
          },
          parameters = {
            stream = true,
          },
          headers = {
            content_type = "application/json",
            home = "${home}",
          },
          schema = {
            model = {
              order = 1,
              type = "enum",
              desc = "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
              default = "oli_model_v2",
            },
            temperature = {
              default = "${home}",
              mapping = "parameters.temperature",
            },
          },
        }
      ]])
    end,
    post_case = child.stop,
  },
})

T["Adapter"] = new_set()

T["Adapter"]["can form parameters from a chat buffer's settings"] = function()
  local result = child.lua([[
    local adapter = require("codecompanion.adapters").extend("openai")
    local result = adapter:map_schema_to_params(_G.chat_buffer_settings)

    -- Ignore these for now
    result.parameters.stream = nil
    result.parameters.stream_options = nil

    return result.parameters
  ]])

  h.eq(child.lua_get([[_G.chat_buffer_settings]]), result)
end

T["Adapter"]["can nest parameters based on an adapter's schema"] = function()
  local result = child.lua([[
    local adapter = require("codecompanion.adapters").extend(_G.test_adapter)
    return adapter:map_schema_to_params(_G.chat_buffer_settings).parameters
  ]])

  local expected = {
    stream = true,
    data = {
      model = "gpt-4-0125-preview",
    },
    options = {
      temperature = 1,
      top_p = 1,
    },
  }

  h.eq(expected, result)
end

T["Adapter"]["can form environment variables"] = function()
  local result = child.lua([[
    local adapter = require("codecompanion.adapters").extend(test_adapter2)
    return adapter:get_env_vars()
  ]])

  h.eq(child.lua_get([[_G.test_adapter2.schema.model.default]]), result.env_replaced.model)
  h.eq(os.getenv("HOME"), result.env_replaced.home)
end

T["Adapter"]["can set environment variables in the adapter"] = function()
  local result = child.lua([[
    adapter = require("codecompanion.adapters").extend(_G.test_adapter2)
    adapter:get_env_vars()

    return adapter:set_env_vars(adapter.url)
  ]])

  h.eq("https://api.oli.ai/v1/chat/oli_model_v2", result)

  local headers = child.lua([[
    return adapter:set_env_vars(adapter.headers)
  ]])

  h.eq({
    content_type = "application/json",
    home = os.getenv("HOME"),
  }, headers)
end

T["Adapter"]["will not set environment variables if it doesn't need to"] = function()
  local params = child.lua([[
    local adapter = require("codecompanion.adapters").extend(test_adapter2)
    adapter:get_env_vars()
    return adapter:set_env_vars(adapter.parameters)
  ]])

  h.eq(child.lua_get([[_G.test_adapter2.parameters]]), params)
end

T["Adapter"]["environment variables can be functions"] = function()
  local result = child.lua([[
    local adapter = require("codecompanion.adapters").extend("openai", {
      env = {
        api_key = function()
          return "test_api_key"
        end,
      }
    })
    return adapter:get_env_vars().env_replaced.api_key
  ]])

  h.eq("test_api_key", result)
end

T["Adapter"]["can update a model on the adapter"] = function()
  local result = child.lua([[
    local adapter = require("codecompanion.adapters").extend(test_adapter)
    return adapter.resolve(adapter).model
  ]])

  h.eq({ name = "gpt-4-0125-preview" }, result)

  result = child.lua([[
    local adapter = require("codecompanion.adapters").extend("openai", {
      schema = {
        model = {
          default = "o4-mini-2025-04-16",
          choices = {
            ["o4-mini-2025-04-16"] = { opts = { can_reason = true } },
            ["o3-mini-2025-01-31"] = { opts = { can_reason = true } },
            ["o3-2025-04-16"] = { opts = { can_reason = true } },
            ["o1-2024-12-17"] = { opts = { can_reason = true } },
          }
        }
      }
    })
    return adapter.resolve(adapter).model
  ]])

  h.eq({
    name = "o4-mini-2025-04-16",
    opts = {
      can_reason = true,
      has_vision = true,
    },
  }, result)
end

T["Adapter"]["can resolve custom adapters"] = function()
  local result = child.lua([[
    require("codecompanion").setup({
      adapters = {
        openai = function()
          return require("codecompanion.adapters").extend("openai", {
            env = {
              api_key = "abc_123"
            }
          })
        end,
      },
      strategies = {
        chat = {
          adapter = "openai",
        }
      }
    })
    return require("codecompanion.adapters").resolve().env.api_key
  ]])

  h.eq("abc_123", result)
end

T["Adapter"]["can pass in the name of the model"] = function()
  local result = child.lua([[
    require("codecompanion").setup({
      strategies = {
        chat = {
          adapter = {
            name = "copilot",
            model = "some_made_up_model"
          }
        }
      }
    })
    return require("codecompanion.adapters").resolve().model.name
  ]])

  h.eq("some_made_up_model", result)
end

T["Adapter"]["utils"] = new_set()

T["Adapter"]["utils"]["can consolidate consecutive messages"] = function()
  child.lua([[
    messages = {
      { role = "system", content = "This is a system prompt" },
      { role = "user", content = "Foo" },
      { role = "user", content = "Bar" },
    }
  ]])

  h.eq({
    { role = "system", content = "This is a system prompt" },
    { role = "user", content = "Foo\n\nBar" },
  }, child.lua_get([[utils.merge_messages(messages)]]))
end

T["Adapter"]["utils"]["can smartly merge tables together"] = function()
  child.lua([[
    messages = {
      {
        role = "user",
        content = {
          content = "Foo",
          tool_id = "123",
        },
      },
      {
        role = "user",
        content = {
          content = "Bar",
          tool_id = "456",
        },
      },
      {
        role = "assistant",
        content = "Foobar ftw!",
      },
    }
  ]])

  h.eq({
    {
      content = {
        {
          content = "Foo",
          tool_id = "123",
        },
        {
          content = "Bar",
          tool_id = "456",
        },
      },
      role = "user",
    },
    {
      content = "Foobar ftw!",
      role = "assistant",
    },
  }, child.lua_get([[utils.merge_messages(messages)]]))
end

T["Adapter"]["utils"]["can consolidate system messages"] = function()
  child.lua([[
    messages = {
      { role = "system", content = "This is a system prompt" },
      { role = "user", content = "Foo" },
      { role = "assistant", content = "Bar" },
      { role = "system", content = "This is ANOTHER system prompt" },
      { role = "user", content = "Baz" },
    }
  ]])

  h.eq({
    { role = "system", content = "This is a system prompt This is ANOTHER system prompt" },
    { role = "user", content = "Foo" },
    { role = "assistant", content = "Bar" },
    { role = "user", content = "Baz" },
  }, child.lua_get([[utils.merge_system_messages(messages)]]))
end

return T
