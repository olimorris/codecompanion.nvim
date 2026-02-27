local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = MiniTest.new_set()

local inline

T["Inline Editor Context"] = new_set({
  hooks = {
    pre_case = function()
      inline = h.setup_inline()
    end,
    post_case = function() end,
  },
})

T["Inline Editor Context"]["can find editor context"] = function()
  local ec = require("codecompanion.interactions.inline.editor_context").new({
    prompt = "#{foo} can you print hello world?",
  })
  ec:find()

  h.eq({ "foo" }, ec.editor_context_items)

  ec.editor_context_items = {}
  ec.prompt = "can you #{foo} #{bar} print hello world?"
  ec:find()

  table.sort(ec.editor_context_items) -- Avoid any ordering issues
  h.eq({ "bar", "foo" }, ec.editor_context_items)
end

T["Inline Editor Context"]["can remove editor context from a prompt"] = function()
  local ec = require("codecompanion.interactions.inline.editor_context").new({
    prompt = "#{foo} can you print hello world?",
  })
  ec:replace()

  h.eq("can you print hello world?", ec.prompt)

  ec.prompt = "are you #{foo} #{bar} working?"
  ec:replace()
  h.eq("are you   working?", ec.prompt)
end

T["Inline Editor Context"]["can add editor context to an inline class"] = function()
  local ec = require("codecompanion.interactions.inline.editor_context").new({
    inline = inline,
    prompt = "can you print hello world?",
  })
  ec.editor_context_items = { "foo" }
  h.eq({ "The output from foo editor context" }, ec:output())
end

return T
