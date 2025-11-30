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
        md_loader = require('codecompanion.actions.md_loader')
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

T["MD Loader"] = new_set()

-- T["MD Loader"]["load_dir loads all md files in a directory"] = function()
--   local result = child.lua([[
--     require("tests.log")
--     return md_loader.load_dir("tests/actions/stubs/", context)
--   ]])
--
--   h.eq(result, 2, "Should load two markdown prompts")
-- end

T["MD Loader"]["parse_frontmatter extracts yaml"] = function()
  local frontmatter = [[---
    strategy: chat
    description: Explain how code in a buffer works
    opts:
      auto_submit: true
      is_default: true
      is_slash_cmd: true
      modes:
        - v
      short_name: explain
      stop_context_insertion: true
      user_prompt: false
    ---
  ]]

  local result = child.lua(
    [[
      return md_loader.parse_frontmatter(...)
  ]],
    { frontmatter }
  )

  h.eq({
    description = "Explain how code in a buffer works",
    opts = {
      auto_submit = true,
      is_default = true,
      is_slash_cmd = true,
      modes = { "v" },
      short_name = "explain",
      stop_context_insertion = true,
      user_prompt = false,
    },
    strategy = "chat",
  }, result, "Frontmatter should be parsed correctly")
end

T["MD Loader"]["parse_prompt extracts system and user prompts"] = function()
  local markdown = [[## system

You are a helpful assistant.

## user

Explain the following code:

```python
def hello_world():
    print("Hello, world!")
```
]]

  local result = child.lua(
    [[
      require("tests.log")
      return md_loader.parse_prompt(...)
  ]],
    { markdown }
  )

  h.eq({
    {
      content = "You are a helpful assistant.",
      role = "system",
    },
    {
      content = 'Explain the following code:\n\n```python\ndef hello_world():\n    print("Hello, world!")\n```',
      role = "user",
    },
  }, result, "Prompts should be parsed correctly")
end

return T
