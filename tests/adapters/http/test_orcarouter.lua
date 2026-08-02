local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["OrcaRouter adapter"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").resolve("orcarouter")
    end,
  },
})

T["OrcaRouter adapter"]["resolves model capabilities on the first request"] = function()
  local adapters = require("codecompanion.adapters")

  adapter.schema.model.default = "openai/gpt-5.5"
  adapter.schema.model.choices = function(_, opts)
    if not (opts and opts.async == false) then
      return {}
    end
    return { ["openai/gpt-5.5"] = { opts = { has_vision = true } } }
  end

  adapter.parameters = {}
  adapters.call_handler(adapter, "setup")

  h.eq(true, adapter.opts.vision)
end

T["OrcaRouter adapter"]["disables vision for models that do not support it"] = function()
  local adapters = require("codecompanion.adapters")

  adapter.schema.model.default = "z-ai/glm-5.2"
  adapter.schema.model.choices = function(_, opts)
    if not (opts and opts.async == false) then
      return {}
    end
    return { ["z-ai/glm-5.2"] = { opts = { has_vision = false } } }
  end

  adapter.parameters = {}
  adapters.call_handler(adapter, "setup")

  h.eq(false, adapter.opts.vision)
end

return T
