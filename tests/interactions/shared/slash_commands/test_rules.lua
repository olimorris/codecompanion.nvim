local new_set = MiniTest.new_set
local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
    end,
    post_once = child.stop,
  },
})

T["cli_render returns rules file paths and @-referenced files"] = function()
  -- Create a temp file that the rules markdown will reference via @
  local included = child.lua("return vim.fn.tempname()")
  child.fn.writefile({ "included content" }, included)

  -- Create a rules markdown file that references the included file
  local rules_file = child.lua("return vim.fn.tempname()")
  child.fn.writefile({
    "## Project Rules",
    "",
    "@" .. included,
    "",
    "Some instructions for the agent",
  }, rules_file)

  local paths = child.lua(string.format(
    [[
    -- Stub vim.ui.select to auto-pick the first item
    vim.ui.select = function(items, _, on_choice)
      on_choice(items[1])
    end

    package.loaded["codecompanion.config"] = {
      rules = {
        parsers = { cli = "cli" },
        test_group = {
          description = "Test rules",
          files = { %q },
        },
        opts = { show_presets = false },
      },
    }

    local result
    local slash = require("codecompanion.interactions.shared.slash_commands.rules")
    slash.cli_render({}, function(p) result = p end)

    return result
  ]],
    rules_file
  ))

  -- Should contain both the rules file itself and the @-referenced file
  h.eq(2, #paths)
  h.eq(true, vim.endswith(paths[1], vim.fn.fnamemodify(rules_file, ":t")))
  h.eq(included, paths[2])
end

return T
