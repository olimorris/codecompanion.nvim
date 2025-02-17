local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = MiniTest.new_set()

local inline

T["Inline Variables"] = new_set({
  hooks = {
    pre_case = function()
      inline = h.setup_inline({
        adapters = {
          mock = {
            name = "mock",
            formatted_name = "Mock",
            roles = {
              llm = "assistant",
              user = "user",
            },
            opts = {
              stream = false,
            },
            url = "http://mock-url",
            headers = {},
            handlers = {
              setup = function(self)
                return true
              end,
              form_parameters = function(self, params, messages)
                return params
              end,
              form_messages = function(self, messages)
                return { messages = messages }
              end,
              inline_output = function(self, data, context)
                return "<response>\n<code><![CDATA[function hello_world()\n  print('Hello World')\nend]]></code>\n<placement>add</placement>\n</response>"
              end,
            },
            schema = {
              model = {
                default = "mock-model",
                choices = {},
              },
            },
          },
        },
        strategies = {
          inline = {
            adapter = "mock",
            variables = {
              ["foo"] = {
                callback = vim.fn.getcwd() .. "/tests/strategies/inline/variables/foo.lua",
                description = "My foo variable",
              },
            },
          },
        },
      })
    end,
    post_case = function() end,
  },
})

T["Inline Variables"]["can find variables"] = function()
  local vars = require("codecompanion.strategies.inline.variables").new({
    prompt = "#foo can you print hello world?",
  })
  vars:find()

  h.eq({ "foo" }, vars.vars)

  vars.vars = {}
  vars.prompt = "can you #foo #bar print hello world?"
  vars:find()

  table.sort(vars.vars) -- Avoid any ordering issues
  h.eq({ "bar", "foo" }, vars.vars)
end

T["Inline Variables"]["can remove variables from a prompt"] = function()
  local vars = require("codecompanion.strategies.inline.variables").new({
    prompt = "#foo can you print hello world?",
  })
  vars:replace()

  h.eq("can you print hello world?", vars.prompt)

  vars.prompt = "are you #foo #bar working?"
  vars:replace()
  h.eq("are you working?", vars.prompt)
end

-- T["Inline Variables"]["can add variables to an inline class"] = function()
--   local vars = require("codecompanion.strategies.inline.variables").new({
--     inline = inline,
--     prompt = "can you print hello world?",
--   })
--   vars.vars = { "foo" }
--   h.eq("are you working?", vars:output())
-- end

return T
