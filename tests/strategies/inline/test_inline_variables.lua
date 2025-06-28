local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = MiniTest.new_set()

local inline

T["Inline Variables"] = new_set({
  hooks = {
    pre_case = function()
      inline = h.setup_inline()
    end,
    post_case = function() end,
  },
})

T["Inline Variables"]["can find variables"] = function()
  local vars = require("codecompanion.strategies.inline.variables").new({
    prompt = "#{foo} can you print hello world?",
  })
  vars:find()

  h.eq({ "foo" }, vars.vars)

  vars.vars = {}
  vars.prompt = "can you #{foo} #{bar} print hello world?"
  vars:find()

  table.sort(vars.vars) -- Avoid any ordering issues
  h.eq({ "bar", "foo" }, vars.vars)
end

T["Inline Variables"]["can remove variables from a prompt"] = function()
  local vars = require("codecompanion.strategies.inline.variables").new({
    prompt = "#{foo} can you print hello world?",
  })
  vars:replace()

  h.eq("can you print hello world?", vars.prompt)

  vars.prompt = "are you #{foo} #{bar} working?"
  vars:replace()
  h.eq("are you   working?", vars.prompt)
end

T["Inline Variables"]["can add variables to an inline class"] = function()
  local vars = require("codecompanion.strategies.inline.variables").new({
    inline = inline,
    prompt = "can you print hello world?",
  })
  vars.vars = { "foo" }
  h.eq({ "The output from foo variable" }, vars:output())
end

return T
