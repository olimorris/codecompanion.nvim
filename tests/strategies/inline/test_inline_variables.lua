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
          },
        },
      })
    end,
    post_case = function() end,
  },
})

T["Inline Variables"]["can find variables"] = function()
  local vars = require("codecompanion.strategies.inline.variables").new({
    prompt = "#buffer can you print hello world?",
  })
  vars:find()

  h.eq({ "buffer" }, vars.vars)

  vars.vars = {}
  vars.prompt = "can you #buffer #chat print hello world?"
  vars:find()

  table.sort(vars.vars)
  h.eq({ "buffer", "chat" }, vars.vars)
end

T["Inline Variables"]["can remove variables from a prompt"] = function()
  local vars = require("codecompanion.strategies.inline.variables").new({
    prompt = "#buffer can you print hello world?",
  })
  vars:replace()

  h.eq("can you print hello world?", vars.prompt)

  vars.prompt = "are you #buffer #chat working?"
  vars:replace()
  h.eq("are you working?", vars.prompt)
end

T["Inline Variables"]["can add variables to an inline class"] = function()
  -- creat
  local vars = require("codecompanion.strategies.inline.variables").new({
    prompt = "can you print hello world?",
  })
  vars.vars = { "foo" }
  vars:add()
end

return T
