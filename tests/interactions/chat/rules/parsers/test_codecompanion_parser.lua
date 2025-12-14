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

T["Claude parser"] = function()
  -- Ensure resolve() would be able to find the built-in claude parser by name
  child.lua([[
    package.loaded['codecompanion.config'] = {
      rules = { parsers = { codecompanion = "codecompanion" } }
    }
  ]])

  -- Create an included temp file
  local included = child.lua("return vim.fn.tempname()")
  child.fn.writefile({ "INCLUDED FILE CONTENT" }, included)

  -- Create the markdown file that references the included file with "@<path>"
  local md = child.lua("return vim.fn.tempname()")
  child.fn.writefile({
    "# My CodeCompanion Parser",
    "",
    "## System Prompt",
    "",
    "Instructions:",
    "- Do something",
    "- Do another thing",
    "",
    "## My other header",
    "",
    "@" .. included,
    "",
    "If this works then this file should be returned as a path",
  }, md)

  -- Run the claude parser on the markdown content and return parsed result
  local parsed = child.lua(string.format(
    [[
      local p = require("codecompanion.interactions.chat.rules.parsers.codecompanion")
      local md = table.concat(vim.fn.readfile(%q), "\n") .. "\n"

      -- Send the content to the parser
      local res = p({ content = md })

      -- Normalize return so we can inspect content and included files
      return { system_prompt = res.system_prompt, content = res.content, included = (res.meta and res.meta.included_files) or {} }
    ]],
    md
  ))

  h.eq(
    table.concat({
      "Instructions:",
      "- Do something",
      "- Do another thing",
    }, "\n"),
    parsed.system_prompt
  )
  h.eq("## My other header\n\n\nIf this works then this file should be returned as a path", parsed.content)
  h.eq(included, parsed.included[1])
end

return T
