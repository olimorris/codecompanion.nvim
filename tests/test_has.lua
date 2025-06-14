local h = require("tests.helpers")

local expect = MiniTest.expect
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
      child.lua([[
        codecompanion = require("codecompanion")
      ]])
    end,
    post_once = child.stop,
  },
})

T["has"] = new_set()

T["has"]["returns TRUE if a feature exists"] = function()
  h.eq(
    true,
    child.lua_get([[
      codecompanion.has("chat")
    ]])
  )
end

T["has"]["returns FALSE if a feature does not exists"] = function()
  h.eq(
    false,
    child.lua_get([[
      codecompanion.has("olimorris")
    ]])
  )
end

T["has"]["returns TRUE for multiple features"] = function()
  h.eq(
    true,
    child.lua_get([[
      codecompanion.has({"chat", "inline-assistant"})
    ]])
  )
end

T["has"]["returns FALSE for multiple features if one doesn't exist"] = function()
  h.eq(
    false,
    child.lua_get([[
      codecompanion.has({"chat", "olimorris"})
    ]])
  )
end

T["has"]["returns a table if the parameter is empty"] = function()
  h.eq(
    "table",
    child.lua_get([[
      type(codecompanion.has())
    ]])
  )
end

return T
