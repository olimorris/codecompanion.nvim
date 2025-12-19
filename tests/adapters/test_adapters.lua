local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
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

T["Adapter"]["can use schema to created nested parameters"] = function()
  local result = child.lua([[
    local adapter = require("codecompanion.adapters").extend("openai", {
      schema = {
        ["reasoning.effort"] = {
          order = 2,
          mapping = "parameters",
          type = "string",
          optional = true,
          default = "medium",
          desc = "Constrains effort on reasoning for reasoning models. Reducing reasoning effort can result in faster responses and fewer tokens used on reasoning in a response.",
          choices = {
            "high",
            "medium",
            "low",
            "minimal",
          }
        }
      }
    })
    return adapter:map_schema_to_params().parameters
  ]])

  local expected = {
    effort = "medium",
  }

  h.eq(expected, result.reasoning)
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
    local utils = require("codecompanion.utils.adapters")
    local adapter = require("codecompanion.adapters").extend(test_adapter2)
    return utils.get_env_vars(adapter)
  ]])

  h.eq(child.lua_get([[_G.test_adapter2.schema.model.default]]), result.env_replaced.model)
  h.eq(os.getenv("HOME"), result.env_replaced.home)
end

T["Adapter"]["can set environment variables in the adapter"] = function()
  local result = child.lua([[
    local utils = require("codecompanion.utils.adapters")
    adapter = require("codecompanion.adapters").extend(_G.test_adapter2)
    utils.get_env_vars(adapter)

    return utils.set_env_vars(adapter, adapter.url)
  ]])

  h.eq("https://api.oli.ai/v1/chat/oli_model_v2", result)

  local headers = child.lua([[
    return utils.set_env_vars(adapter, adapter.headers)
  ]])

  h.eq({
    content_type = "application/json",
    home = os.getenv("HOME"),
  }, headers)
end

T["Adapter"]["will not set environment variables if it doesn't need to"] = function()
  local params = child.lua([[
    local utils = require("codecompanion.utils.adapters")
    local adapter = require("codecompanion.adapters").extend(test_adapter2)
    utils.get_env_vars(adapter)
    return utils.set_env_vars(adapter, adapter.parameters)
  ]])

  h.eq(child.lua_get([[_G.test_adapter2.parameters]]), params)
end

T["Adapter"]["environment variables can be functions"] = function()
  local result = child.lua([[
    local utils = require("codecompanion.utils.adapters")
    local adapter = require("codecompanion.adapters").extend("openai", {
      env = {
        api_key = function()
          return "test_api_key"
        end,
      }
    })
    return utils.get_env_vars(adapter).env_replaced.api_key
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

T["Adapter"]["can update schema"] = function()
  local adapter = require("codecompanion.adapters").extend("openai", {
    schema = {
      model = {
        default = "my-new-adapter",
        choices = {
          "my-new-adapter",
          "my-other-adapter",
        },
      },
    },
  })

  h.eq("my-new-adapter", adapter.schema.model.default)
  h.eq("my-new-adapter", adapter.schema.model.choices[1])
end

T["Adapter"]["can resolve custom adapters"] = function()
  local result = child.lua([[
    require("codecompanion").setup({
      adapters = {
        http = {
          openai = function()
            return require("codecompanion.adapters").extend("openai", {
              env = {
                api_key = "abc_123"
              }
            })
          end,
        }
      },
      interactions = {
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
    h.setup_plugin({
      interactions = {
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

T["Adapter"]["can extend an adapter"] = function()
  local result = child.lua([[
    return require("codecompanion.adapters").extend("openai", {
      env = {
        api_key = "test_api_key",
      }
    }).env.api_key
  ]])

  h.eq("test_api_key", result)
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

T["Adapter"]["call_handler"] = new_set()

T["Adapter"]["call_handler"]["works with nested handlers"] = function()
  local result = child.lua([[
    local adapters = require("codecompanion.adapters")

    -- Create an adapter with nested handlers
    local adapter = {
      name = "test",
      type = "http",
      handlers = {
        request = {
          build_messages = function(self, messages)
            return { processed = true, messages = messages }
          end,
          build_parameters = function(self, params, messages)
            return { processed_params = params }
          end
        },
        response = {
          parse_chat = function(self, data, tools)
            return { status = "success", output = { content = data } }
          end,
          parse_tokens = function(self, data)
            return 42
          end
        }
      }
    }

    return {
      messages = adapters.call_handler(adapter, "build_messages", { "hello" }),
      parameters = adapters.call_handler(adapter, "build_parameters", { temp = 1 }, {}),
      chat = adapters.call_handler(adapter, "parse_chat", "test data", {}),
      tokens = adapters.call_handler(adapter, "parse_tokens", {})
    }
  ]])

  h.eq({ processed = true, messages = { "hello" } }, result.messages)
  h.eq({ processed_params = { temp = 1 } }, result.parameters)
  h.eq({ status = "success", output = { content = "test data" } }, result.chat)
  h.eq(42, result.tokens)
end

T["Adapter"]["call_handler"]["works with old flat handler structure"] = function()
  local result = child.lua([[
    local adapters = require("codecompanion.adapters")

    -- Create an adapter with old flat handler structure
    local adapter = {
      name = "test",
      type = "http",
      handlers = {
        form_messages = function(self, messages)
          return { old_format = true, messages = messages }
        end,
        form_parameters = function(self, params, messages)
          return { old_params = params }
        end,
        chat_output = function(self, data, tools)
          return { status = "success", output = { content = data } }
        end,
        tokens = function(self, data)
          return 100
        end
      }
    }

    -- Call using new names, should map to old names via compatibility layer
    return {
      messages = adapters.call_handler(adapter, "build_messages", { "world" }),
      parameters = adapters.call_handler(adapter, "build_parameters", { temp = 2 }, {}),
      chat = adapters.call_handler(adapter, "parse_chat", "old data", {}),
      tokens = adapters.call_handler(adapter, "parse_tokens", {})
    }
  ]])

  h.eq({ old_format = true, messages = { "world" } }, result.messages)
  h.eq({ old_params = { temp = 2 } }, result.parameters)
  h.eq({ status = "success", output = { content = "old data" } }, result.chat)
  h.eq(100, result.tokens)
end

T["Adapter"]["call_handler"]["returns nil for missing handlers"] = function()
  local result = child.lua([[
    local adapters = require("codecompanion.adapters")

    local adapter = {
      name = "test",
      type = "http",
      handlers = {}
    }

    return {
      missing = adapters.call_handler(adapter, "non_existent_handler", "data"),
      also_missing = adapters.call_handler(adapter, "another_missing", "more data")
    }
  ]])

  h.eq(nil, result.missing)
  h.eq(nil, result.also_missing)
end

T["Adapter"]["call_handler"]["passes adapter as first argument"] = function()
  local result = child.lua([[
    local adapters = require("codecompanion.adapters")

    local adapter = {
      name = "test_adapter",
      custom_field = "test_value",
      type = "http",
      handlers = {
        lifecycle = {
          setup = function(self)
            return {
              name = self.name,
              custom = self.custom_field
            }
          end
        }
      }
    }

    return adapters.call_handler(adapter, "setup")
  ]])

  h.eq({
    name = "test_adapter",
    custom = "test_value",
  }, result)
end

T["Adapter"]["call_handler"]["works with lifecycle handlers"] = function()
  local result = child.lua([[
    local adapters = require("codecompanion.adapters")

    local adapter = {
      name = "test",
      type = "http",
      handlers = {
        lifecycle = {
          setup = function(self)
            return true
          end,
          on_exit = function(self, data)
            return "cleaned_up_" .. data.status
          end,
          teardown = function(self)
            return "torn_down"
          end
        }
      }
    }

    return {
      setup = adapters.call_handler(adapter, "setup"),
      on_exit = adapters.call_handler(adapter, "on_exit", { status = 200 }),
      teardown = adapters.call_handler(adapter, "teardown")
    }
  ]])

  h.eq(true, result.setup)
  h.eq("cleaned_up_200", result.on_exit)
  h.eq("torn_down", result.teardown)
end

T["Adapter"]["call_handler"]["works with tool handlers"] = function()
  local result = child.lua([[
    local adapters = require("codecompanion.adapters")

    local adapter = {
      name = "test",
      type = "http",
      roles = { tool = "tool" },
      handlers = {
        -- Add a lifecycle handler to make it clear this is new format
        lifecycle = {},
        tools = {
          format_calls = function(self, tools)
            return { formatted = true, tools = tools }
          end,
          format_response = function(self, tool_call, output)
            return {
              role = self.roles.tool,
              content = output,
              tool_call_id = tool_call.id
            }
          end
        }
      }
    }

    return {
      format = adapters.call_handler(adapter, "format_calls", { { name = "test_tool" } }),
      response = adapters.call_handler(adapter, "format_response", { id = "call_123" }, "tool output")
    }
  ]])

  h.eq({
    formatted = true,
    tools = { { name = "test_tool" } },
  }, result.format)

  h.eq({
    role = "tool",
    content = "tool output",
    tool_call_id = "call_123",
  }, result.response)
end

T["Adapter"]["call_handler"]["works with tools in old flat format"] = function()
  -- This test is is unneccesasry but checking there's no weird edge cases

  local result = child.lua([[
    local adapters = require("codecompanion.adapters")

    -- Real old flat format - has tools namespace but no lifecycle/request/response
    local adapter = {
      name = "test",
      type = "http",
      roles = { tool = "tool" },
      handlers = {
        -- Flat handlers (old format indicators)
        form_messages = function(self, messages)
          return { messages = messages }
        end,
        chat_output = function(self, data, tools)
          return { status = "success", output = { content = data } }
        end,
        -- Tools in namespace (but still old format because no lifecycle/request/response)
        tools = {
          format_tool_calls = function(self, tools)
            return { old_format = true, tools = tools }
          end,
          output_response = function(self, tool_call, output)
            return {
              role = self.roles.tool,
              content = "old:" .. output
            }
          end
        }
      }
    }

    return {
      format = adapters.call_handler(adapter, "format_calls", { { name = "old_tool" } }),
      response = adapters.call_handler(adapter, "format_response", { id = "123" }, "data")
    }
  ]])

  h.eq({
    old_format = true,
    tools = { { name = "old_tool" } },
  }, result.format)

  h.eq({
    role = "tool",
    content = "old:data",
  }, result.response)
end

T["Adapter"]["call_handler"]["handles multiple arguments correctly"] = function()
  local result = child.lua([[
    local adapters = require("codecompanion.adapters")

    local adapter = {
      name = "test",
      type = "http",
      handlers = {
        request = {
          build_parameters = function(self, params, messages)
            return {
              adapter_name = self.name,
              params_count = #params,
              messages_count = #messages
            }
          end
        }
      }
    }

    return adapters.call_handler(
      adapter,
      "build_parameters",
      { "p1", "p2", "p3" },
      { "m1", "m2" }
    )
  ]])

  h.eq({
    adapter_name = "test",
    params_count = 3,
    messages_count = 2,
  }, result)
end

T["Adapter"]["call_handler"]["works without arguments"] = function()
  local result = child.lua([[
    local adapters = require("codecompanion.adapters")

    local adapter = {
      name = "test",
      type = "http",
      handlers = {
        lifecycle = {
          teardown = function(self)
            return "cleaned"
          end
        }
      }
    }

    return adapters.call_handler(adapter, "teardown")
  ]])

  h.eq("cleaned", result)
end

return T
