local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = MiniTest.new_set()

local child = MiniTest.new_child_neovim()
T["Keymaps"] = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        config = require("tests.config")
        change_adapter = require("codecompanion.interactions.chat.keymaps.change_adapter")
      ]])
    end,
    post_once = child.stop,
  },
})

T["Keymaps"]["change_adapter"] = new_set()

T["Keymaps"]["change_adapter"]["get_adapters_list returns correct list"] = function()
  child.lua([[h.setup_plugin()]])

  local list = child.lua([[return change_adapter.get_adapters_list("test_adapter")]])

  h.eq(list[1], "test_adapter")
  h.expect_tbl_contains("copilot", list)
  h.expect_tbl_contains("anthropic", list)
end

T["Keymaps"]["change_adapter"]["current adapter appears once at front"] = function()
  child.lua([[h.setup_plugin()]])
  local list = child.lua([[return change_adapter.get_adapters_list("test_adapter")]])

  h.eq(list[1], "test_adapter")

  local count = 0
  for _, adapter in ipairs(list) do
    if adapter == "test_adapter" then
      count = count + 1
    end
  end
  h.eq(count, 1)
end

T["Keymaps"]["change_adapter"]["list_http_models returns correct list with object models"] = function()
  local result = child.lua([[
    h.setup_plugin()
    config.adapters.http.opts.show_model_choices = true

    local mock_adapter = {
      schema = {
        model = {
          default = "gpt-4",
          choices = {
            "mistral-large-latest",
            ["pixtral-large-latest"] = { opts = { has_vision = true } },
            ["gpt-4"] = { formatted_name = "GPT-4" },
            ["gpt-3.5-turbo"] = { formatted_name = "GPT-3.5 Turbo" },
          }
        }
      }
    }

    local list = change_adapter.list_http_models(mock_adapter)
    if not list then return nil end

    local ids = {}
    for _, model in ipairs(list) do
      local id = type(model) == "table" and model.id or model
      table.insert(ids, id)
    end
    return { first_id = ids[1], count = #ids, has_formatted_name = list[1].formatted_name ~= nil }
  ]])

  h.eq(result.first_id, "gpt-4")
  h.eq(result.count, 4)
  h.expect_truthy(result.has_formatted_name)
end

T["Keymaps"]["change_adapter"]["list_http_models returns correct list with string models"] = function()
  local result = child.lua([[
    h.setup_plugin()
    config.adapters.http.opts.show_model_choices = true

    local mock_adapter = {
      schema = {
        model = {
          default = "gpt-4",
          choices = {
            "mistral-large-latest",
            "pixtral-large-latest",
            "gpt-4",
            "gpt-3.5-turbo",
          }
        }
      }
    }

    local list = change_adapter.list_http_models(mock_adapter)
    if not list then return nil end

    local names = {}
    for _, model in ipairs(list) do
      table.insert(names, model)
    end
    return { first_id = names[1], count = #names }
  ]])

  h.eq(result.first_id, "gpt-4")
  h.eq(result.count, 4)
end

T["Keymaps"]["change_adapter"]["list_http_models returns nil when < 2 models"] = function()
  local result = child.lua([[
    h.setup_plugin()
    local adapter = {
      schema = {
        model = {
          default = "gpt-4",
          choices = { "gpt-4" }
        }
      }
    }
    return change_adapter.list_http_models(adapter) == nil
  ]])

  h.expect_truthy(result)
end

T["Keymaps"]["change_adapter"]["list_acp_models returns correct structure"] = function()
  local result = child.lua([[
    h.setup_plugin()

    -- Mock the models data
    local models_data = {
      availableModels = {
        {
          description = "Sonnet 4.5 · Best for everyday tasks",
          modelId = "default",
          name = "Default (recommended)"
        },
        {
          description = "Opus 4.5 · Most capable for complex work",
          modelId = "opus",
          name = "Opus"
        },
        {
          description = "Haiku 4.5 · Fastest for quick answers",
          modelId = "haiku",
          name = "Haiku"
        }
      },
      currentModelId = "default"
    }

    -- Create a mock connection object with get_models method
    local acp_connection = {
      get_models = function(self)
        return models_data
      end
    }

    local models = change_adapter.list_acp_models(acp_connection)
    return {
      has_available_models = models.availableModels ~= nil,
      available_count = #models.availableModels,
      current_model_id = models.currentModelId,
      first_model_id = models.availableModels[1].modelId
    }
  ]])

  h.expect_truthy(result.has_available_models)
  h.eq(result.available_count, 3)
  h.eq(result.current_model_id, "default")
  h.eq(result.first_model_id, "default")
end

T["Keymaps"]["change_adapter"]["list_acp_models returns nil when < 2 keys in models"] = function()
  local result = child.lua([[
    h.setup_plugin()

    local acp_connection = {
      get_models = function(self)
        return { currentModelId = "default" }
      end
    }

    return change_adapter.list_acp_models(acp_connection) == nil
  ]])

  h.expect_truthy(result)
end

return T
