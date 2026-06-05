local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["Azure OpenAI adapter"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").resolve("azure_openai")
    end,
  },
})

T["Azure OpenAI adapter"]["makes optional tool parameters strict"] = function()
  local run_skill_script = {
    type = "function",
    ["function"] = {
      name = "run_skill_script",
      description = "Run a skill script",
      parameters = {
        type = "object",
        properties = {
          args = {
            type = "object",
          },
        },
      },
    },
  }
  local tools = { run_skill_script = { run_skill_script } }
  local output = adapter.handlers.form_tools(adapter, tools)
  local parameters = output.tools[1]["function"].parameters

  h.eq({ "args" }, parameters.required)
  h.eq(false, parameters.additionalProperties)
  h.eq(nil, parameters.strict)
  h.eq(true, output.tools[1]["function"].strict)
  h.eq({ "object", "null" }, parameters.properties.args.type)
end

return T
