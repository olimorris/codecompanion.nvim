local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = MiniTest.new_set()

local child = MiniTest.new_child_neovim()
T["Adapter UI"] = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        config = require("codecompanion.config")
        adapter_ui = require("codecompanion.adapters.ui")
      ]])
    end,
    post_once = child.stop,
  },
})

T["Adapter UI"]["get_adapters_list returns correct list"] = function()
  child.lua([[h.setup_plugin()]])

  local list = child.lua([[return adapter_ui.get_adapters_list("test_adapter")]])

  h.eq(list[1], "test_adapter")
  h.expect_tbl_contains("copilot", list)
  h.expect_tbl_contains("anthropic", list)
end

T["Adapter UI"]["hidden adapters are excluded from the list"] = function()
  child.lua([[h.setup_plugin()]])

  local list = child.lua([[return adapter_ui.get_adapters_list("test_adapter")]])

  h.expect_tbl_contains("anthropic", list)
  h.eq(false, vim.tbl_contains(list, "tavily"))
end

T["Adapter UI"]["an adapter set to false in hidden is shown"] = function()
  child.lua([[
    h.setup_plugin()
    config.adapters.http.opts.hidden.tavily = false
  ]])

  local list = child.lua([[return adapter_ui.get_adapters_list("test_adapter")]])

  h.expect_tbl_contains("tavily", list)
end

T["Adapter UI"]["current adapter appears once at front"] = function()
  child.lua([[h.setup_plugin()]])
  local list = child.lua([[return adapter_ui.get_adapters_list("test_adapter")]])

  h.eq(list[1], "test_adapter")

  local count = 0
  for _, adapter in ipairs(list) do
    if adapter == "test_adapter" then
      count = count + 1
    end
  end
  h.eq(count, 1)
end

T["Adapter UI"]["list_http_models returns correct list with object models"] = function()
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

    local list = adapter_ui.list_http_models(mock_adapter)
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

T["Adapter UI"]["list_http_models returns correct list with string models"] = function()
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

    local list = adapter_ui.list_http_models(mock_adapter)
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

T["Adapter UI"]["list_http_models returns nil when < 2 models"] = function()
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
    return adapter_ui.list_http_models(adapter) == nil
  ]])

  h.expect_truthy(result)
end

T["Adapter UI"]["select_model marks the current ACP model and returns the picked id"] = function()
  local result = child.lua([[
    h.setup_plugin()

    local picked = {}
    vim.ui.select = function(items, opts, on_choice)
      picked.labels = vim.tbl_map(opts.format_item, items)
      on_choice(items[2])
    end

    adapter_ui.select_model({
      adapter = { type = "acp" },
      acp_models = {
        availableModels = {
          { modelId = "default", name = "Default", description = "Sonnet" },
          { modelId = "opus", name = "Opus" },
        },
        currentModelId = "default",
      },
      on_choice = function(model_id)
        picked.model_id = model_id
      end,
    })
    return picked
  ]])

  h.eq({ "* Default - Sonnet", "  Opus" }, result.labels)
  h.eq("opus", result.model_id)
end

T["Adapter UI"]["select_model DOES NOT open the picker for a single ACP model"] = function()
  local result = child.lua([[
    h.setup_plugin()

    local result = { opened = false, called = false }
    vim.ui.select = function()
      result.opened = true
    end

    adapter_ui.select_model({
      adapter = { type = "acp" },
      acp_models = { availableModels = { { modelId = "default", name = "Default" } }, currentModelId = "default" },
      on_choice = function(model_id)
        result.called = model_id == nil
      end,
    })
    return result
  ]])

  h.eq({ opened = false, called = true }, result)
end

return T
