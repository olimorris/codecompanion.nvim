local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = MiniTest.new_set()

local inline

T["Inline"] = new_set({
  hooks = {
    pre_case = function()
      inline = h.setup_inline({
        adapters = {
          fake_adapter = { name = "fake_adapter", schema = {} },
        },
      })
    end,
    post_case = function() end,
  },
})

T["Inline"]["can parse XML output correctly"] = function()
  local xml = inline:parse_output([[<response>
      <code>function test() end</code>
      <placement>add</placement>
    </response>]])

  h.eq("function test() end", xml.code)
  h.eq("add", xml.placement)
end

T["Inline"]["can parse markdown output correctly"] = function()
  local xml = inline:parse_output([[```xml
<response>
  <code>function test() end</code>
  <placement>add</placement>
</response>
```]])

  h.eq("function test() end", xml.code)
  h.eq("add", xml.placement)
end

T["Inline"]["can parse Ollama output correctly"] = function()
  local xml = inline:parse_output(
    "```xml\n<response>\n  <code><![CDATA[\n/**\n * Executes an action based on the current action type.\n */\n]]></code>\n  <language>php</language>\n  <placement>before</placement>\n</response>\n```"
  )
  h.eq(
    [[

/**
 * Executes an action based on the current action type.
 */
]],
    xml.code
  )
  h.eq("before", xml.placement)
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

  inline:prompt("Hello World")

  h.eq(#inline.prompts, 4)
  -- System prompt
  h.expect_starts_with("## CONTEXT", inline.prompts[1].content)
  -- Visual selection
  h.eq(
    "For context, this is the code that I've visually selected in the buffer, which is relevant to my prompt:\n\n```lua\nlocal x = 1\n```",
    inline.prompts[3].content
  )
  -- User prompt
  h.eq("<user_prompt>Hello World</user_prompt>", inline.prompts[#inline.prompts].content)
end

T["Inline"]["generates correct prompt structure"] = function()
  local submitted_prompts = {}

  -- Mock the submit function
  function inline:submit(prompts)
    submitted_prompts = prompts
  end

  inline:prompt("Test prompt")

  h.eq(#submitted_prompts, 2) -- Should be a system prompt and the user prompt
  h.eq(submitted_prompts[1].role, "system")
  h.eq(submitted_prompts[2].role, "user")
  h.eq(submitted_prompts[2].content, "<user_prompt>Test prompt</user_prompt>")
end

T["Inline"]["the first word can be an adapter"] = function()
  -- Mock the submit function
  local submitted_prompts = {}
  function inline:submit(prompts)
    submitted_prompts = prompts
  end

  -- Adapter is the default
  h.eq(inline.adapter.name, "test_adapter")

  inline:prompt("fake_adapter print hello world")

  -- Adapter has been changed
  h.eq("fake_adapter", inline.adapter.name)

  -- Adapter is removed from the prompt
  h.eq(submitted_prompts[2].content, "<user_prompt>print hello world</user_prompt>")
end

T["Inline"]["can be called from the action palette"] = function()
  local prompt = {
    name = "test",
    strategy = "inline",
    prompts = {
      {
        role = "user",
        content = "Action Palette test",
      },
    },
  }

  local strategy = require("codecompanion.strategies").new({
    context = inline.context,
    selected = prompt,
  })
  strategy:start("inline")

  -- System prompt is added
  h.eq(2, #strategy.called.prompts)

  -- User prompt is added
  h.eq("Action Palette test", strategy.called.prompts[2].content)
end

T["Inline"]["integration"] = function()
  -- Mock the submit function
  local submitted_prompts = {}
  function inline:submit(prompts)
    submitted_prompts = prompts
  end

  inline:prompt("#foo can you print hello world?")

  h.eq("The output from foo variable", submitted_prompts[2].content)
  h.eq("<user_prompt>can you print hello world?</user_prompt>", submitted_prompts[3].content)
end

return T
