local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = MiniTest.new_set()

local child = MiniTest.new_child_neovim()

T["Inline"] = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        config = require("tests.config")

        -- Setup inline in child process
        inline = h.setup_inline({
          adapters = {
            http = {
              fake_adapter = { name = "fake_adapter" },
            },
          },
        })
      ]])
    end,
    post_case = function()
      child.lua([[inline = nil]])
    end,
    post_once = child.stop,
  },
})

T["Inline"]["can parse json output correctly"] = function()
  local json_str = [[{
  "code": "function test() end",
  "placement": "add"
}]]

  local json = child.lua([[return inline:parse_output(...)]], { json_str })
  h.eq("function test() end", json.code)
  h.eq("add", json.placement)
end

T["Inline"]["can parse markdown output correctly"] = function()
  local markdown_str = [[```json
{
  "code": "function test() end",
  "placement": "add"
}
```]]

  local json = child.lua([[return inline:parse_output(...)]], { markdown_str })
  h.eq("function test() end", json.code)
  h.eq("add", json.placement)
end

T["Inline"]["can parse Ollama output correctly"] = function()
  local ollama_response_str = "{\n"
    .. '  "code": "\\n\\n/**\\n * Executes an action based on the current action type.\\n */\\n",\n'
    .. '  "language": "lua",\n'
    .. '  "placement": "before"\n'
    .. "}"

  local json = child.lua_get([[inline:parse_output(...)]], { ollama_response_str })
  local expected_code_block = [[


/**
 * Executes an action based on the current action type.
 */
]]

  h.eq(expected_code_block, json.code)
  h.eq("before", json.placement)
end

T["Inline"]["handles different placements"] = function()
  -- Test 'add' placement
  child.lua([[inline:place("add")]])
  local pos = child.lua([[return inline.classification.pos]])
  local buffer_context = child.lua([[return inline.buffer_context]])
  h.eq(pos, {
    line = buffer_context.end_line + 1,
    col = 0,
    bufnr = buffer_context.bufnr,
  })

  -- Test 'replace' placement
  child.lua([[inline:place("replace")]])
  pos = child.lua([[return inline.classification.pos]])
  buffer_context = child.lua([[return inline.buffer_context]])
  h.eq(pos, {
    line = buffer_context.start_line,
    col = buffer_context.start_col,
    bufnr = buffer_context.bufnr,
  })

  -- Test 'before' placement
  child.lua([[inline:place("before")]])
  pos = child.lua([[return inline.classification.pos]])
  buffer_context = child.lua([[return inline.buffer_context]])
  h.eq(pos, {
    line = buffer_context.start_line - 1,
    col = math.max(0, buffer_context.start_col - 1),
    bufnr = buffer_context.bufnr,
  })
end

T["Inline"]["forms correct prompts"] = function()
  child.lua([[
    local prompts = {
      {
        role = "user",
        content = "test prompt",
        opts = { contains_code = true },
      },
    }

    inline.prompts = prompts
    inline.buffer_context.is_visual = true
    inline.buffer_context.lines = { "local x = 1" }

    inline:prompt("Hello World")
  ]])

  local prompts = child.lua([[return inline.prompts]])
  h.eq(#prompts, 4)
  -- System prompt
  h.expect_starts_with("You are a knowledgeable", prompts[1].content)
  -- Visual selection
  h.eq(
    "For context, this is the code that I've visually selected in the buffer, which is relevant to my prompt:\n<code>\n```lua\nlocal x = 1\n```\n</code>",
    prompts[3].content
  )
  -- User prompt
  h.eq("<prompt>Hello World</prompt>", prompts[#prompts].content)
end

T["Inline"]["generates correct prompt structure"] = function()
  child.lua([[
    -- Mock the submit function
    _G.submitted_prompts = {}
    function inline:submit(prompts)
      _G.submitted_prompts = prompts
    end

    inline:prompt("Test prompt")
  ]])

  local submitted_prompts = child.lua([[return _G.submitted_prompts]])
  h.eq(#submitted_prompts, 2) -- Should be a system prompt and the user prompt
  h.eq(submitted_prompts[1].role, "system")
  h.eq(submitted_prompts[2].role, "user")
  h.eq(submitted_prompts[2].content, "<prompt>Test prompt</prompt>")
end

T["Inline"]["the first word can be an adapter"] = function()
  child.lua([[
    -- Mock the submit function
    _G.submitted_prompts = {}
    function inline:submit(prompts)
      _G.submitted_prompts = prompts
    end
  ]])

  -- Adapter is the default
  h.eq(child.lua([[return inline.adapter.name]]), "test_adapter")

  child.lua([[inline:prompt("fake_adapter print hello world")]])

  -- Adapter has been changed
  h.eq("fake_adapter", child.lua([[return inline.adapter.name]]))

  -- Adapter is removed from the prompt
  local submitted_prompts = child.lua([[return _G.submitted_prompts]])
  h.eq(submitted_prompts[2].content, "<prompt>print hello world</prompt>")
end

T["Inline"]["can be called from the action palette"] = function()
  child.lua([[
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

    local interaction = require("codecompanion.interactions").new({
      buffer_context = inline.buffer_context,
      selected = prompt,
    })
    interaction:start("inline")

    _G.test_interaction = interaction
  ]])

  -- System prompt is added
  h.eq(2, child.lua([[return #_G.test_interaction.called.prompts]]))

  -- User prompt is added
  h.eq("Action Palette test", child.lua([[return _G.test_interaction.called.prompts[2].content]]))
end

T["Inline"]["integration"] = function()
  child.lua([[
    -- Mock the submit function
    _G.submitted_prompts = {}
    function inline:submit(prompts)
      _G.submitted_prompts = prompts
    end

    inline:prompt("#{foo} can you print hello world?")
  ]])

  local submitted_prompts = child.lua([[return _G.submitted_prompts]])
  h.eq("The output from foo variable", submitted_prompts[2].content)
  h.eq("<prompt>can you print hello world?</prompt>", submitted_prompts[3].content)
end

T["Inline"]["can parse adapter syntax"] = function()
  child.lua([[
    _G.submitted_prompts = {}
    function inline:submit(prompts)
      _G.submitted_prompts = prompts
    end

    -- Mock the buffer variable to return predictable content
    _G.original_buffer_variable = require("codecompanion.config").interactions.inline.variables.buffer
    require("codecompanion.config").interactions.inline.variables.buffer = {
      callback = function()
        return "mocked buffer content"
      end,
      description = "Mock buffer for testing",
    }
  ]])

  -- Default adapter
  h.eq(child.lua([[return inline.adapter.name]]), "test_adapter")

  child.lua([[inline:prompt("adapter=fake_adapter #{buffer} print hello world")]])
  h.eq("fake_adapter", child.lua([[return inline.adapter.name]]))

  -- Should be system + buffer content + user prompt
  local submitted_prompts = child.lua([[return _G.submitted_prompts]])
  h.eq(3, #submitted_prompts)

  h.eq("mocked buffer content", submitted_prompts[2].content)

  -- Check We've cleaned up the prompt
  h.eq("<prompt>print hello world</prompt>", submitted_prompts[#submitted_prompts].content)

  -- Restore original buffer variable
  child.lua([[
    require("codecompanion.config").interactions.inline.variables.buffer = _G.original_buffer_variable
  ]])
end

return T
