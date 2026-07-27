local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["Kimi adapter"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").resolve("kimi")
    end,
  },
})

T["Kimi adapter"]["resolves model capabilities on the first request"] = function()
  local adapters = require("codecompanion.adapters")

  adapter.schema.model.default = "kimi-k2.7-code"
  adapter.schema.model.choices = function(_, opts)
    if not (opts and opts.async == false) then
      return {}
    end
    return { ["kimi-k2.7-code"] = { opts = { has_vision = true } } }
  end

  adapter.parameters = {}
  adapters.call_handler(adapter, "setup")

  h.eq(true, adapter.opts.vision)
end

return T
