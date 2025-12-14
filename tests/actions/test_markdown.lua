local h = require("tests.helpers")
local new_set = MiniTest.new_set
local T = new_set()
local child = MiniTest.new_child_neovim()

T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        codecompanion = h.setup_plugin()
        markdown = require('codecompanion.actions.markdown')
        context = {
          filetype = "markdown",
          bufnr = vim.api.nvim_create_buf(false, true),
          cwd = vim.fn.getcwd(),
        }
      ]])
    end,
    post_once = child.stop,
  },
})

T["Markdown"] = new_set()

T["Markdown"]["parse_frontmatter extracts yaml"] = function()
  local frontmatter = [[---
name: Explain
strategy: chat
description: Explain how code in a buffer works
opts:
  auto_submit: true
  is_slash_cmd: true
  adapter:
    name: copilot
    model: gpt-4.1
  modes:
    - v
  alias: explain
  stop_context_insertion: true
  user_prompt: false
---
  ]]

  local result = child.lua(
    [[
      require("tests.log")
      return markdown.parse_frontmatter(...)
    ]],
    { frontmatter }
  )

  h.eq(result, {
    interaction = "chat",
    description = "Explain how code in a buffer works",
    name = "Explain",
    opts = {
      auto_submit = true,
      adapter = { name = "copilot", model = "gpt-4.1" },
      is_slash_cmd = true,
      modes = { "v" },
      alias = "explain",
      stop_context_insertion = true,
      user_prompt = false,
    },
  }, "Frontmatter should be parsed correctly")
end

T["Markdown"]["parse_frontmatter extracts interactions"] = function()
  local frontmatter = [[---
name: Explain
interaction: chat
description: Explain how code in a buffer works
---
  ]]

  local result = child.lua(
    [[
      return markdown.parse_frontmatter(...)
  ]],
    { frontmatter }
  )

  h.eq(result, {
    description = "Explain how code in a buffer works",
    name = "Explain",
    interaction = "chat",
  }, "Frontmatter should be parsed correctly")
end

T["Markdown"]["parse_frontmatter extracts context"] = function()
  local frontmatter = [[---
name: Explain
strategy: chat
description: Explain how code in a buffer works
context:
  - type: file
    path:
      - lua/codecompanion/health.lua
      - lua/codecompanion/http.lua
  - type: file
    path: lua/codecompanion/schema.lua
---
  ]]

  local result = child.lua(
    [[
      return markdown.parse_frontmatter(...)
  ]],
    { frontmatter }
  )

  h.eq(result, {
    context = {
      {
        type = "file",
        path = { -- This can be a string or a table of values
          "lua/codecompanion/health.lua",
          "lua/codecompanion/http.lua",
        },
      },
      {
        type = "file",
        path = "lua/codecompanion/schema.lua",
      },
    },
    description = "Explain how code in a buffer works",
    name = "Explain",
    interaction = "chat",
  }, "Frontmatter with context should be parsed correctly")
end

T["Markdown"]["parse_prompt extracts system and user prompts"] = function()
  local markdown = [[## system

You are a helpful assistant.

## user

Explain the following code:

```python
def hello_world():
    print("Hello, world!")
```

## user

Here is another user prompt.
]]

  local result = child.lua(
    [[
      return markdown.parse_prompt(...)
  ]],
    { markdown }
  )

  h.eq(result, {
    {
      content = "You are a helpful assistant.",
      role = "system",
    },
    {
      content = 'Explain the following code:\n\n```python\ndef hello_world():\n    print("Hello, world!")\n```',
      role = "user",
    },
    {
      content = "Here is another user prompt.",
      role = "user",
    },
  }, "Prompts should be parsed correctly")
end

T["Markdown"]["parse_prompt formats workflow prompts"] = function()
  local frontmatter = {
    opts = {
      is_workflow = true,
    },
  }

  local markdown = [[## system

System prompt

## user

User prompt 1

## user

User prompt 2

## user

User prompt 3
]]

  local result = child.lua(
    [[
      return markdown.parse_prompt(...)
  ]],
    { markdown, frontmatter }
  )

  h.eq(result, {
    {
      {
        content = "System prompt",
        role = "system",
      },
      {
        content = "User prompt 1",
        role = "user",
      },
    },
    {
      {
        content = "User prompt 2",
        role = "user",
      },
    },
    {
      {
        content = "User prompt 3",
        role = "user",
      },
    },
  }, "Workflow prompts should be parsed correctly")
end

T["Markdown"]["parse_prompt workflow prompts with options"] = function()
  local frontmatter = {
    opts = {
      is_workflow = true,
    },
  }

  local markdown = [[
## user

```yaml opts
auto_submit: true
```

User prompt 1

## user

```yaml opts
auto_submit: false
```

User prompt 2

## user

User prompt 3

## user

```yaml opts
adapter:
  name: copilot
  model: gpt-4.1
```

User prompt 4
]]

  local result = child.lua(
    [[
      return markdown.parse_prompt(...)
  ]],
    { markdown, frontmatter }
  )

  h.eq(result, {
    {
      {
        content = "User prompt 1",
        role = "user",
        opts = {
          auto_submit = true,
        },
      },
    },
    {
      {
        content = "User prompt 2",
        role = "user",
        opts = {
          auto_submit = false,
        },
      },
    },
    {
      {
        content = "User prompt 3",
        role = "user",
      },
    },
    {
      {
        content = "User prompt 4",
        role = "user",
        opts = {
          adapter = {
            name = "copilot",
            model = "gpt-4.1",
          },
        },
      },
    },
  }, "Workflow prompts should be parsed correctly")
end

T["Markdown"]["parse_prompt ignores incorrect roles"] = function()
  local markdown = [[## foo

You are a helpful assistant.

## bar

No I'm not.
]]

  local result = child.lua(
    [[
      return markdown.parse_prompt(...)
  ]],
    { markdown }
  )

  h.eq(vim.NIL, result, "No prompts should be parsed for incorrect roles")
end

T["Markdown"]["load_from_dir loads all markdown files in a directory"] = function()
  local result = child.lua([[
    return markdown.load_from_dir("tests/actions/stubs/", context)
  ]])

  local expected = {
    {
      description = "Explain how code in a buffer works",
      name = "Test Prompt",
      opts = {
        auto_submit = true,
        is_slash_cmd = true,
        modes = { "v" },
        alias = "explain",
        stop_context_insertion = true,
        user_prompt = false,
      },
      path = "tests/actions/stubs/test_prompt.md",
      prompts = {
        {
          content = "You are a helpful assistant.",
          role = "system",
        },
        {
          content = 'Explain the following code:\n\n```python\ndef hello_world():\n    print("Hello, world!")\n```',
          role = "user",
        },
        {
          content = "Here is another user prompt.",
          role = "user",
        },
      },
      interaction = "chat",
    },
  }

  h.eq(expected, result, "Should load prompts from markdown files in directory")
end

T["Markdown"]["resolve_placeholders()"] = new_set()

T["Markdown"]["resolve_placeholders()"]["resolves context placeholders"] = function()
  child.lua([[
    _G.test_context = {
      bufnr = 42,
      filetype = "lua",
    }
  ]])

  local result = child.lua([[
    local item = {
      name = "Test",
      path = "/tmp/test.md",
      prompts = {
        { role = "user", content = "Buffer ${context.bufnr} has type ${context.filetype}" },
      },
    }
    return markdown.resolve_placeholders(item, _G.test_context)
  ]])

  h.eq(result.prompts[1].content, "Buffer 42 has type lua")
end

T["Markdown"]["resolve_placeholders()"]["loads and resolves from lua files"] = function()
  child.lua([[
    _G.test_dir = vim.fn.tempname()
    vim.fn.mkdir(_G.test_dir, "p")

    vim.fn.writefile({
      "return {",
      "  get_name = function(args)",
      "    return 'Hello from helper'",
      "  end,",
      "  static_value = 'Static data',",
      "}",
    }, vim.fs.joinpath(_G.test_dir, "helpers.lua"))
  ]])

  local result = child.lua([[
    local item = {
      name = "Test",
      path = vim.fs.joinpath(_G.test_dir, "test.md"),
      prompts = {
        { role = "user", content = "Function: ${helpers.get_name}, Static: ${helpers.static_value}" },
      },
    }
    return markdown.resolve_placeholders(item, context)
  ]])

  h.eq(result.prompts[1].content, "Function: Hello from helper, Static: Static data")
end

T["Markdown"]["resolve_placeholders()"]["handles multiple lua files"] = function()
  child.lua([[
    _G.test_dir = vim.fn.tempname()
    vim.fn.mkdir(_G.test_dir, "p")

    vim.fn.writefile({
      "return { value = 'from shared' }",
    }, vim.fs.joinpath(_G.test_dir, "shared.lua"))
    vim.fn.writefile({
      "return { value = 'from utils' }",
    }, vim.fs.joinpath(_G.test_dir, "utils.lua"))
  ]])

  local result = child.lua([[
    local item = {
      name = "Test",
      path = vim.fs.joinpath(_G.test_dir, "test.md"),
      prompts = {
        { role = "user", content = "Shared: ${shared.value}, Utils: ${utils.value}" },
      },
    }
    return markdown.resolve_placeholders(item, context)
  ]])

  h.eq(result.prompts[1].content, "Shared: from shared, Utils: from utils")

  -- Cleanup
  child.lua([[
    vim.fn.delete("/tmp/test_multi", "rf")
  ]])
end

T["Markdown"]["resolve_placeholders()"]["handles nested prompts"] = function()
  child.lua([[
    _G.test_context = {
      bufnr = 99,
      filetype = "python",
    }
  ]])

  local result = child.lua([[
    local item = {
      name = "Test",
      path = "/tmp/test.md",
      prompts = {
        { role = "system", content = "System for buffer ${context.bufnr}" },
        { role = "user", content = "User prompt with ${context.filetype}" },
        { role = "user", content = "Another with ${context.bufnr} and ${context.filetype}" },
      },
    }
    return markdown.resolve_placeholders(item, _G.test_context)
  ]])

  h.eq(result.prompts[1].content, "System for buffer 99")
  h.eq(result.prompts[2].content, "User prompt with python")
  h.eq(result.prompts[3].content, "Another with 99 and python")
end

T["Markdown"]["resolve_placeholders()"]["handles non-existent placeholders gracefully"] = function()
  local result = child.lua([[
    local item = {
      name = "Test",
      path = "/tmp/test.md",
      prompts = {
        { role = "user", content = "Missing: ${nonexistent.value}" },
      },
    }
    return markdown.resolve_placeholders(item, context)
  ]])

  -- Should remain unchanged when placeholder can't be resolved
  h.eq(result.prompts[1].content, "Missing: ${nonexistent.value}")
end

return T
