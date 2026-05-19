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

T["CLI parser"] = function()
  child.lua([[
    package.loaded['codecompanion.config'] = {
      rules = { parsers = { cli = "cli" } }
    }
  ]])

  -- Create an included temp file
  local included = child.lua("return vim.fn.tempname()")
  child.fn.writefile({ "INCLUDED FILE CONTENT" }, included)

  -- Create the markdown file that references the included file with "@<path>"
  local md = child.lua("return vim.fn.tempname()")
  child.fn.writefile({
    "## My CLI Test File",
    "",
    "@" .. included,
    "",
    "This text should not appear in the parsed content",
  }, md)

  local parsed = child.lua(string.format(
    [[
    local p = require("codecompanion.interactions.shared.rules.parsers.cli")
    local md = table.concat(vim.fn.readfile(%q), "\n") .. "\n"

    local res = p({ content = md })

    return { content = res.content, included = (res.meta and res.meta.included_files) or {} }
  ]],
    md
  ))

  -- Content should be empty — CLI parser only extracts file paths
  h.eq(parsed.content, "")
  h.eq(parsed.included[1], included)
end

return T
