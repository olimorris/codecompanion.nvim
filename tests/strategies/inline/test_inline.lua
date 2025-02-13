local codecompanion = require("codecompanion")
local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = MiniTest.new_set()

local inline

local mock_adapter = {
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
}

T["Inline"] = new_set({
  hooks = {
    pre_case = function()
      inline = require("codecompanion.strategies.inline").new({
        adapter = mock_adapter,
        context = {
          winnr = 0,
          bufnr = 0,
          filetype = "lua",
          start_line = 1,
          end_line = 1,
          start_col = 0,
          end_col = 0,
        },
      })
    end,
    post_case = function() end,
  },
})

T["Inline"]["can parse XML output correctly"] = function()
  local code, placement = inline:parse_output([[
    <response>
      <code>function test() end</code>
      <placement>add</placement>
    </response>
  ]])

  h.eq("function test() end", code)
  h.eq("add", placement)
end

T["Inline"]["can parse markdown output correctly"] = function()
  local code, placement = inline:parse_output([[
```xml
<response>
  <code>function test() end</code>
  <placement>add</placement>
</response>
```
  ]])

  h.eq("function test() end", code)
  h.eq("add", placement)
end

T["Inline"]["handles different placements"] = function()
  -- Test 'add' placement
  inline:place("add")
  h.eq(inline.classification.pos, {
    line = inline.context.end_line + 1,
    col = 0,
    bufnr = inline.context.bufnr,
  })

  -- Test 'replace' placement
  inline:place("replace")
  h.eq(inline.classification.pos, {
    line = inline.context.start_line,
    col = inline.context.start_col,
    bufnr = inline.context.bufnr,
  })

  -- Test 'before' placement
  inline:place("before")
  h.eq(inline.classification.pos, {
    line = inline.context.start_line - 1,
    col = math.max(0, inline.context.start_col - 1),
    bufnr = inline.context.bufnr,
  })
end

T["Inline"]["forms correct prompts"] = function()
  local prompts = {
    {
      role = "user",
      content = "test prompt",
      opts = { contains_code = true },
    },
  }

  inline.prompts = prompts
  inline.context.is_visual = true
  inline.context.lines = { "local x = 1" }

  local formed_prompts = inline:make_ext_prompts()
  h.eq(#formed_prompts, 2) -- One for the prompt, one for the visual selection
  h.eq("test prompt", formed_prompts[1].content)
  h.eq(
    "For context, this is some code that I've selected in the buffer which is relevant to my prompt:\n\n```lua\nlocal x = 1\n```",
    formed_prompts[2].content
  )
end

return T
