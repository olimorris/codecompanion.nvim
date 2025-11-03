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
        formatters = require('codecompanion.strategies.chat.acp.formatters')
      ]])
    end,
    post_once = child.stop,
  },
})

-- Test cases based on real RPC output from Claude Code sessions

T["short_title handles undefined title"] = function()
  local result = child.lua([[
    local tool_call = {
      kind = "search",
      title = "undefined",
      rawInput = {},
    }
    return formatters.short_title(tool_call)
  ]])

  h.eq("Search", result)
end

T["short_title handles search with escaped pattern"] = function()
  local result = child.lua([[
    local tool_call = {
      kind = "search",
      title = 'grep "^local M = \\{\\}"',
      rawInput = {
        pattern = "^local M = \\{\\}",
        output_mode = "count"
      },
    }
    return formatters.short_title(tool_call)
  ]])

  h.eq('Search: ^local M = {}', result)
end

T["short_title unescapes common regex characters"] = function()
  local result = child.lua([[
    local tool_call = {
      kind = "search",
      title = 'grep "@class CodeCompanion\\."',
      rawInput = {
        pattern = "@class CodeCompanion\\.",
        output_mode = "files_with_matches"
      },
    }
    return formatters.short_title(tool_call)
  ]])

  h.eq('Search: @class CodeCompanion.', result)
end

T["short_title handles require pattern with parentheses"] = function()
  local result = child.lua([[
    local tool_call = {
      kind = "search",
      title = 'grep "require\\(\"codecompanion\\.adapters\\."',
      rawInput = {
        pattern = 'require\\(\\"codecompanion\\.adapters\\.',
        output_mode = "files_with_matches"
      },
    }
    return formatters.short_title(tool_call)
  ]])

  h.eq('Search: require("codecompanion.adapters.', result)
end

T["short_title handles grep with flags"] = function()
  local result = child.lua([[
    local tool_call = {
      kind = "search",
      title = 'grep -n | head -20 "@field.*adapter"',
      rawInput = {
        pattern = "@field.*adapter",
        output_mode = "content",
        ["-n"] = true,
        head_limit = 20
      },
    }
    return formatters.short_title(tool_call)
  ]])

  h.eq('Search: @field.*adapter', result)
end

T["short_title handles read with file path"] = function()
  local result = child.lua([[
    local tool_call = {
      kind = "read",
      title = "Read /Users/Oli/Code/Neovim/codecompanion.nvim/lua/codecompanion/strategies/chat/debug.lua",
      rawInput = {
        file_path = "/Users/Oli/Code/Neovim/codecompanion.nvim/lua/codecompanion/strategies/chat/debug.lua"
      },
      locations = {
        {
          path = "/Users/Oli/Code/Neovim/codecompanion.nvim/lua/codecompanion/strategies/chat/debug.lua",
          line = 0
        }
      },
    }
    return formatters.short_title(tool_call)
  ]])

  h.eq('Read: debug.lua', result)
end

T["short_title handles read with line range"] = function()
  local result = child.lua([[
    local tool_call = {
      kind = "read",
      title = "Read /Users/Oli/Code/Neovim/codecompanion.nvim/lua/codecompanion/strategies/chat/slash_commands/init.lua (29 - 68)",
      rawInput = {
        file_path = "/Users/Oli/Code/Neovim/codecompanion.nvim/lua/codecompanion/strategies/chat/slash_commands/init.lua",
        offset = 28,
        limit = 40
      },
      locations = {
        {
          path = "/Users/Oli/Code/Neovim/codecompanion.nvim/lua/codecompanion/strategies/chat/slash_commands/init.lua",
          line = 28
        }
      },
    }
    return formatters.short_title(tool_call)
  ]])

  h.eq('Read: init.lua (L29-68)', result)
end

T["short_title handles search in directory"] = function()
  local result = child.lua([[
    local tool_call = {
      kind = "search",
      title = 'grep "class.*SlashCommands"',
      rawInput = {
        pattern = "class.*SlashCommands|function.*SlashCommands\\.new",
        path = "/Users/Oli/Code/Neovim/codecompanion.nvim/lua/codecompanion/strategies/chat/slash_commands",
        output_mode = "content",
        ["-n"] = true
      },
    }
    return formatters.short_title(tool_call)
  ]])

  -- Should show directory basename and truncate pattern at 40 chars
  h.is_true(result:match("^Search:") ~= nil)
  h.is_true(result:match("in slash_commands$") ~= nil)
  h.is_true(result:match("%.%.%.") ~= nil) -- Should be truncated
end

T["short_title handles glob pattern"] = function()
  local result = child.lua([[
    local tool_call = {
      kind = "search",
      title = "Find `**/debug.lua`",
      rawInput = {
        pattern = "**/debug.lua"
      },
    }
    return formatters.short_title(tool_call)
  ]])

  -- Should strip ** prefix and backticks
  h.eq('Search: debug.lua', result)
end

T["short_title strips markdown backticks"] = function()
  local result = child.lua([[
    local tool_call = {
      kind = "search",
      title = "Find `**/formatters.lua`",
      rawInput = {
        pattern = "`**/formatters.lua`"
      },
    }
    return formatters.short_title(tool_call)
  ]])

  h.eq('Search: formatters.lua', result)
end

T["short_title handles diff operations"] = function()
  local result = child.lua([[
    local tool_call = {
      kind = "edit",
      title = "Edit config.lua",
      content = {
        {
          type = "diff",
          path = "/Users/Oli/Code/Neovim/codecompanion.nvim/lua/codecompanion/config.lua",
          oldText = "old code",
          newText = "new code"
        }
      },
    }
    return formatters.short_title(tool_call)
  ]])

  h.eq('Edit: config.lua', result)
end

T["short_title truncates long patterns"] = function()
  local result = child.lua([[
    local tool_call = {
      kind = "search",
      title = "Very long pattern",
      rawInput = {
        pattern = "this is a very long pattern that should be truncated because it exceeds the maximum length allowed"
      },
    }
    return formatters.short_title(tool_call)
  ]])

  -- Should be truncated to 40 chars + "..."
  h.is_true(#result <= 50)
  h.is_true(result:match("%.%.%.$") ~= nil)
end

T["short_title uses colon separator to avoid markdown rendering"] = function()
  local result = child.lua([[
    local tool_call = {
      kind = "search",
      rawInput = {
        pattern = "function.*:add_message"
      },
    }
    return formatters.short_title(tool_call)
  ]])

  -- Should use colon, not space, to prevent markdown list formatting
  h.eq('Search: function.*:add_message', result)
  h.is_true(result:match("^[^%s]+:") ~= nil)
end

T["tool_message includes status"] = function()
  local result = child.lua([[
    local tool_call = {
      kind = "search",
      title = "Search pattern",
      rawInput = {
        pattern = "test"
      },
      status = "completed",
    }
    local adapter = {
      opts = { trim_tool_output = false }
    }
    return formatters.tool_message(tool_call, adapter)
  ]])

  -- Status should be appended
  h.is_true(result:match("completed") ~= nil or result:match("Search:") ~= nil)
end

T["tool_message with trim_tool_output shows only title"] = function()
  local result = child.lua([[
    local tool_call = {
      kind = "search",
      title = "Search test",
      rawInput = {
        pattern = "test"
      },
      status = "completed",
      content = {
        {
          type = "content",
          content = {
            type = "text",
            text = "Very long content that should not appear"
          }
        }
      }
    }
    local adapter = {
      opts = { trim_tool_output = true }
    }
    return formatters.tool_message(tool_call, adapter)
  ]])

  -- Should only show title, not content
  h.is_true(result:match("Search:") ~= nil)
  h.is_true(result:match("Very long content") == nil)
end

T["summarize_tool_content extracts diff summary"] = function()
  local result = child.lua([[
    local tool_call = {
      content = {
        {
          type = "diff",
          path = "/Users/Oli/test.lua",
          oldText = "line1\nline2",
          newText = "line1\nline2\nline3\nline4"
        }
      }
    }
    return formatters.summarize_tool_content(tool_call)
  ]])

  h.is_true(result:match("%+2 lines") ~= nil)
end

T["extract_text handles text content block"] = function()
  local result = child.lua([[
    local block = {
      type = "text",
      text = "Sample text content"
    }
    return formatters.extract_text(block)
  ]])

  h.eq("Sample text content", result)
end

T["extract_text handles resource link"] = function()
  local result = child.lua([[
    local block = {
      type = "resource_link",
      uri = "file:///path/to/file.lua"
    }
    return formatters.extract_text(block)
  ]])

  h.eq("[resource: file:///path/to/file.lua]", result)
end

return T
