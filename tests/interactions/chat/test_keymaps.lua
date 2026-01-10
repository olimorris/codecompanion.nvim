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

T["Keymaps"]["change_adapter"]["get_models_list returns correct list with object models"] = function()
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

T["Keymaps"]["change_adapter"]["get_models_list returns correct list with string models"] = function()
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

-- T["Keymaps"]["change_adapter"]["get_commands_list returns correct list"] = function()
--   local list = child.lua([[
--     h.setup_plugin()
--     local adapter = {
--       commands = {
--         selected = "code",
--         code = {},
--         chat = {},
--         test = {},
--       }
--     }
--     return change_adapter.get_commands_list(adapter)
--   ]])
--
--   h.eq(#list, 3)
--   h.expect_tbl_contains("code", list)
--   h.expect_tbl_contains("chat", list)
--   h.expect_tbl_contains("test", list)
-- end

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

T["Keymaps"]["change_adapter"]["get_models_list returns nil when < 2 models"] = function()
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

-- T["Keymaps"]["change_adapter"]["get_commands_list returns nil when < 2 commands"] = function()
--   local result = child.lua([[
--     h.setup_plugin()
--     local adapter = {
--       commands = {
--         selected = "code",
--       }
--     }
--     return change_adapter.get_commands_list(adapter) == nil
--   ]])
--
--   h.expect_truthy(result)
-- end

return T
