local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = MiniTest.new_set()

local inline

T["Inline"] = new_set({
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

T["Inline"]["can parse XML output correctly"] = function()
  local xml = inline:parse_output([[
    <response>
      <code>function test() end</code>
      <placement>add</placement>
    </response>
  ]])

  h.eq("function test() end", xml.code)
  h.eq("add", xml.placement)
end

T["Inline"]["can parse markdown output correctly"] = function()
  local xml = inline:parse_output([[
```xml
<response>
  <code>function test() end</code>
  <placement>add</placement>
</response>
```
  ]])

  h.eq("function test() end", xml.code)
  h.eq("add", xml.placement)
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

T["Inline"]["generates correct prompt structure"] = function()
  local submitted_prompts = {}

  -- Mock the submit function
  function inline:submit(prompts)
    submitted_prompts = prompts
  end

  -- Simulate running the user prompt through the command line
  local user_prompt = {
    args = "Test prompt",
    fargs = { "Test", "prompt" },
  }
  inline:prompt(user_prompt)

  h.eq(#submitted_prompts, 2) -- Should be a system prompt and the user prompt
  h.eq(submitted_prompts[1].role, "system")
  h.eq(submitted_prompts[2].role, "user")
  h.eq(submitted_prompts[2].content, "<user_prompt>Test prompt</user_prompt>")
end

T["Inline"]["the first word can be an adapter"] = function()
  local submitted_prompts = {}

  -- Mock the submit function
  function inline:submit(prompts)
    submitted_prompts = prompts
  end

  -- Adapter is the default
  h.eq(inline.adapter.name, "mock")

  -- Simulate running the user prompt through the command line
  local user_prompt = {
    args = "copilot print hello world",
    fargs = { "copilot", "print", "hello", "world" },
  }
  inline:prompt(user_prompt)

  -- Adapter has been changed
  h.eq(inline.adapter.name, "copilot")

  -- Adapter is removed from the prompt
  h.eq(submitted_prompts[2].content, "<user_prompt>print hello world</user_prompt>")
end

return T
