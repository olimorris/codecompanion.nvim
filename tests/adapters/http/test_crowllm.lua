local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["CrowLLM adapter"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").resolve("crowllm")
    end,
  },
})

T["CrowLLM adapter"]["resolves vision from the selected model"] = function()
  local adapters = require("codecompanion.adapters")

  adapter.schema.model.default = "kimi-k3"
  adapter.schema.model.choices = function(_, opts)
    if not (opts and opts.async == false) then
      return {}
    end
    return { ["kimi-k3"] = { opts = { has_vision = true } } }
  end

  adapter.parameters = {}
  adapters.call_handler(adapter, "setup")

  h.eq(true, adapter.opts.vision)
end

T["CrowLLM adapter"]["keeps a visible note when the model has no vision"] = function()
  local adapters = require("codecompanion.adapters")

  adapter.opts.vision = false
  local messages = {
    {
      role = "user",
      content = "look at this",
      _meta = { tag = "image" },
      context = { mimetype = "image/png" },
    },
  }

  local built = adapters.call_handler(adapter, "build_messages", { messages = messages })
  h.eq(1, #built)
  h.expect_match("image omitted", built[1].content)
end

return T
