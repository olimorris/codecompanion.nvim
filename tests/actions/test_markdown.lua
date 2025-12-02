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
  is_default: true
  is_slash_cmd: true
  adapter:
    name: copilot
    model: gpt-4.1
  modes:
    - v
  short_name: explain
  stop_context_insertion: true
  user_prompt: false
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
    opts = {
      auto_submit = true,
      adapter = { name = "copilot", model = "gpt-4.1" },
      is_default = true,
      is_slash_cmd = true,
      modes = { "v" },
      short_name = "explain",
      stop_context_insertion = true,
      user_prompt = false,
    },
    strategy = "chat",
  }, "Frontmatter should be parsed correctly")
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
        is_default = true,
        is_slash_cmd = true,
        modes = { "v" },
        short_name = "explain",
        stop_context_insertion = true,
        user_prompt = false,
      },
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
      strategy = "chat",
    },
  }

  h.eq(expected, result, "Should load prompts from markdown files in directory")
end

return T
