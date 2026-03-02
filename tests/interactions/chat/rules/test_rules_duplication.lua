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

T["Rules duplication"] = new_set({})

-- This test demonstrates the bug where a file referenced via @include in CLAUDE.md
-- gets added twice: once as a direct rules file and once as an included file.
-- The issue is that direct rules files use <rules>path</rules> IDs while
-- included files use <file>path</file> IDs, so has_context() doesn't detect duplicates.
T["Rules duplication"]["file referenced in both rules.files and @include should not be duplicated"] = function()
  -- Create a temp directory for our test files
  local tmpdir = child.lua("return vim.fn.tempname()")
  child.fn.mkdir(tmpdir)

  -- Create AGENTS.md - this will be both directly listed AND referenced via @include
  local agents_md = vim.fs.joinpath(tmpdir, "AGENTS.md")
  child.fn.writefile({ "# Agents", "", "This is the agents content" }, agents_md)

  -- Create CLAUDE.md that references AGENTS.md via @include syntax
  local claude_md = vim.fs.joinpath(tmpdir, "CLAUDE.md")
  child.fn.writefile({ "# Claude", "", "@" .. agents_md, "", "Additional Claude content" }, claude_md)

  -- Set up and run the rules with both files in the files list
  -- This mimics the default config where both CLAUDE.md and AGENTS.md are listed
  child.lua(string.format(
    [[
    local h = require("tests.helpers")
    local cc = h.setup_plugin()
    local config = require("codecompanion.config")

    config.rules = vim.tbl_deep_extend("force", config.rules or {}, {
      default = {
        description = "test duplication",
        files = {
          { path = %q, parser = "claude" },  -- CLAUDE.md with claude parser
          %q,  -- AGENTS.md directly listed
        },
        is_preset = true,
      },
      parsers = {
        claude = "claude",
      },
      opts = {
        chat = {
          enabled = true,
          autoload = "default",
        },
        show_presets = true,
      },
    })

    _G.test_chat = cc.chat()
    _G.test_messages = _G.test_chat and _G.test_chat.messages or nil
  ]],
    claude_md,
    agents_md
  ))

  local messages = child.lua_get([[_G.test_messages]])

  -- Count how many times AGENTS.md content appears in messages
  local agents_count = 0
  local agents_ids = {}
  for _, msg in ipairs(messages) do
    if msg.context and msg.context.id then
      -- Check if this message is related to AGENTS.md
      if msg.context.id:find("AGENTS.md") then
        agents_count = agents_count + 1
        table.insert(agents_ids, msg.context.id)
      end
    end
  end

  -- The bug: AGENTS.md appears twice with different ID formats:
  -- 1. <rules>/path/to/AGENTS.md</rules> (from direct listing in add_context)
  -- 2. <file>/path/to/AGENTS.md</file> (from @include via add_files_or_buffers)
  --
  -- The fix should make add_files_or_buffers use <rules> IDs so has_context()
  -- properly detects the duplicate.
  --
  -- This test will FAIL until the bug is fixed, demonstrating that
  -- AGENTS.md is being added twice instead of once.

  -- Print actual IDs for debugging
  if agents_count ~= 1 then
    print("AGENTS.md found " .. agents_count .. " times with IDs:")
    for _, id in ipairs(agents_ids) do
      print("  - " .. id)
    end
  end

  h.eq(agents_count, 1)
end

return T
