local h = require("tests.helpers")

local T = MiniTest.new_set()
local child = MiniTest.new_child_neovim()

T["Utils"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        utils = require('codecompanion.utils')
      ]])
    end,
    post_once = child.stop,
  },
})

T["Utils"]["extract_placeholders()"] = MiniTest.new_set()

T["Utils"]["extract_placeholders()"]["extracts single placeholder"] = function()
  local result = child.lua([[return utils.extract_placeholders("Hello ${name}!")]])
  h.eq(result, { "name" })
end

T["Utils"]["extract_placeholders()"]["extracts multiple placeholders"] = function()
  local result = child.lua([[return utils.extract_placeholders("${greeting} ${name}, today is ${day}")]])
  h.eq(result, { "greeting", "name", "day" })
end

T["Utils"]["extract_placeholders()"]["extracts dot-notation placeholders"] = function()
  local result = child.lua([[return utils.extract_placeholders("${context.code} and ${utils.helper}")]])
  h.eq(result, { "context.code", "utils.helper" })
end

T["Utils"]["extract_placeholders()"]["handles nested paths"] = function()
  local result = child.lua([[return utils.extract_placeholders("${context.bufnr} and ${item.opts.auto_submit}")]])
  h.eq(result, { "context.bufnr", "item.opts.auto_submit" })
end

T["Utils"]["extract_placeholders()"]["removes duplicates"] = function()
  local result = child.lua([[return utils.extract_placeholders("${name} is ${name}")]])
  h.eq(result, { "name" })
end

T["Utils"]["extract_placeholders()"]["returns empty table when no placeholders"] = function()
  local result = child.lua([[return utils.extract_placeholders("Hello world!")]])
  h.eq(result, {})
end

T["Utils"]["extract_placeholders()"]["handles empty string"] = function()
  local result = child.lua([[return utils.extract_placeholders("")]])
  h.eq(result, {})
end

T["Utils"]["extract_all_placeholders()"] = MiniTest.new_set()

T["Utils"]["extract_all_placeholders()"]["extracts from string"] = function()
  local result = child.lua([[return utils.extract_all_placeholders("Hello ${name}!")]])
  h.eq(result, { "name" })
end

T["Utils"]["extract_all_placeholders()"]["extracts from nested tables"] = function()
  local result = child.lua([[
    return utils.extract_all_placeholders({
      { role = "system", content = "You are ${role}" },
      { role = "user", content = "Code: ${code}" },
    })
  ]])
  h.eq(result, { "role", "code" })
end

T["Utils"]["extract_all_placeholders()"]["extracts from deeply nested tables"] = function()
  local result = child.lua([[
    return utils.extract_all_placeholders({
      prompts = {
        { role = "system", content = "Hello ${name}" },
        { role = "user", content = "Use ${context.code} and ${utils.format}" },
      },
      opts = {
        description = "Test ${context.bufnr}",
      },
    })
  ]])

  -- Check all expected placeholders are present (order doesn't matter)
  h.eq(#result, 4)
  h.expect_tbl_contains("name", result)
  h.expect_tbl_contains("context.code", result)
  h.expect_tbl_contains("utils.format", result)
  h.expect_tbl_contains("context.bufnr", result)
end

T["Utils"]["extract_all_placeholders()"]["removes duplicates across nested structures"] = function()
  local result = child.lua([[
    return utils.extract_all_placeholders({
      { content = "${name}" },
      { content = "${age}" },
      { content = "${name}" },
    })
  ]])
  h.eq(result, { "name", "age" })
end

T["Utils"]["extract_all_placeholders()"]["returns empty table for non-placeholder content"] = function()
  local result = child.lua([[
    return utils.extract_all_placeholders({
      { role = "system", content = "No placeholders here" },
      { role = "user", content = "Still none" },
    })
  ]])
  h.eq(result, {})
end

T["Utils"]["replace_placeholders()"] = MiniTest.new_set()

T["Utils"]["replace_placeholders()"]["replaces placeholder in string"] = function()
  local result = child.lua([[
    return utils.replace_placeholders("Hello ${name}!", { name = "World" })
  ]])
  h.eq(result, "Hello World!")
end

T["Utils"]["replace_placeholders()"]["replaces multiple placeholders in string"] = function()
  local result = child.lua([[
    return utils.replace_placeholders(
      "${greeting} ${name}, today is ${day}",
      { greeting = "Hello", name = "Alice", day = "Monday" }
    )
  ]])
  h.eq(result, "Hello Alice, today is Monday")
end

T["Utils"]["replace_placeholders()"]["replaces placeholders in table"] = function()
  child.lua([[
    _G.test_table = {
      { role = "system", content = "You are a ${role}" },
      { role = "user", content = "My name is ${name}" },
    }
    utils.replace_placeholders(_G.test_table, { role = "helper", name = "Bob" })
  ]])

  local result = child.lua([[return _G.test_table]])
  h.eq(result, {
    { role = "system", content = "You are a helper" },
    { role = "user", content = "My name is Bob" },
  })
end

T["Utils"]["replace_placeholders()"]["replaces dot-notation placeholders"] = function()
  local result = child.lua([[
    return utils.replace_placeholders(
      "Code: ${context.code}",
      { ["context.code"] = "function() end" }
    )
  ]])
  h.eq(result, "Code: function() end")
end

T["Utils"]["replace_placeholders()"]["handles nested table replacement"] = function()
  child.lua([[
    _G.nested = {
      prompts = {
        { content = "Buffer ${context.bufnr}" },
      },
      opts = {
        description = "Uses ${shared.helper}",
      },
    }
    utils.replace_placeholders(_G.nested, {
      ["context.bufnr"] = "123",
      ["shared.helper"] = "format()",
    })
  ]])

  local result = child.lua([[return _G.nested]])
  h.eq(result, {
    prompts = {
      { content = "Buffer 123" },
    },
    opts = {
      description = "Uses format()",
    },
  })
end

T["Utils"]["replace_placeholders()"]["does not modify when no placeholders match"] = function()
  local result = child.lua([[
    return utils.replace_placeholders("Hello ${name}!", { other = "value" })
  ]])
  h.eq(result, "Hello ${name}!")
end

T["Utils"]["replace_placeholders()"]["handles special characters in placeholder names"] = function()
  local result = child.lua([[
    return utils.replace_placeholders(
      "Value: ${my-special_var.123}",
      { ["my-special_var.123"] = "test" }
    )
  ]])
  h.eq(result, "Value: test")
end

T["Utils"]["replace_placeholders()"]["handles percent signs in replacement values"] = function()
  local result = child.lua([[
    return utils.replace_placeholders(
      '(<a href="https://my.test.page/tester.php?login=${email}" title="Test Page">%20</a>)',
      { email = "testuser%40testing.org" }
    )
  ]])
  h.eq(result, '(<a href="https://my.test.page/tester.php?login=testuser%40testing.org" title="Test Page">%20</a>)')
end

T["Utils"]["replace_placeholders()"]["handles simple percent signs in replacement"] = function()
  local result = child.lua([[
    return utils.replace_placeholders(
      "Encoded: ${value}",
      { value = "%20" }
    )
  ]])
  h.eq(result, "Encoded: %20")
end

T["Utils"]["resolve_nested_value()"] = MiniTest.new_set()

T["Utils"]["resolve_nested_value()"]["resolves top-level value"] = function()
  local result = child.lua([[
    local tbl = { name = "Alice" }
    return utils.resolve_nested_value(tbl, "name")
  ]])
  h.eq(result, "Alice")
end

T["Utils"]["resolve_nested_value()"]["resolves nested value"] = function()
  local result = child.lua([[
    local tbl = { context = { bufnr = 5 } }
    return utils.resolve_nested_value(tbl, "context.bufnr")
  ]])
  h.eq(result, 5)
end

T["Utils"]["resolve_nested_value()"]["resolves deeply nested value"] = function()
  local result = child.lua([[
    local tbl = { item = { opts = { auto_submit = true } } }
    return utils.resolve_nested_value(tbl, "item.opts.auto_submit")
  ]])
  h.eq(result, true)
end

T["Utils"]["resolve_nested_value()"]["returns nil for non-existent path"] = function()
  local result = child.lua([[
    local tbl = { context = { bufnr = 5 } }
    return utils.resolve_nested_value(tbl, "context.missing.path")
  ]])
  h.eq(result, vim.NIL)
end

T["Utils"]["resolve_nested_value()"]["returns nil for missing top-level key"] = function()
  local result = child.lua([[
    local tbl = { name = "Alice" }
    return utils.resolve_nested_value(tbl, "missing")
  ]])
  h.eq(result, vim.NIL)
end

T["Utils"]["resolve_nested_value()"]["resolves function values"] = function()
  local result = child.lua([[
    local tbl = { shared = { code = function() return "test" end } }
    local resolved = utils.resolve_nested_value(tbl, "shared.code")
    return type(resolved)
  ]])
  h.eq(result, "function")
end

T["Utils"]["resolve_nested_value()"]["handles numeric keys in path"] = function()
  local result = child.lua([[
    local tbl = { items = { [1] = "first", [2] = "second" } }
    return utils.resolve_nested_value(tbl, "items.1")
  ]])
  h.eq(result, vim.NIL) -- Won't resolve numeric keys as strings
end

return T
