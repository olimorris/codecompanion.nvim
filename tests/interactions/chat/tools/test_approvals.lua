local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        -- Mock the config module BEFORE requiring approvals
        package.loaded['codecompanion.config'] = {
          interactions = {
            chat = {
              tools = {
                some_tool = {},
                protected_tool = {
                  opts = {
                    protect = true,
                  },
                },
                run_command = {
                  opts = {
                    require_cmd_approval = true,
                    safe_commands = { "git status", "ls" },
                  },
                },
              },
            },
          },
        }

        Approvals = require('codecompanion.interactions.chat.tools.approvals')
      ]])
    end,
    post_case = function()
      -- Reset state between tests
      child.lua([[
        -- Force reload the module to reset the approved cache
        package.loaded['codecompanion.interactions.chat.tools.approvals'] = nil
        Approvals = require('codecompanion.interactions.chat.tools.approvals')
      ]])
    end,
    post_once = child.stop,
  },
})

T["always()"] = new_set()

T["always()"]["creates approval cache for new buffer"] = function()
  child.lua([[
    Approvals:always(1, { tool_name = 'read_file' })
  ]])

  local result = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'read_file' })
  ]])

  h.eq(result, true)
end

T["always()"]["adds multiple tools to same buffer"] = function()
  child.lua([[
    Approvals:always(1, { tool_name = 'read_file' })
    Approvals:always(1, { tool_name = 'insert_edit_into_file' })
  ]])

  local read_approved = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'read_file' })
  ]])
  local insert_approved = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'insert_edit_into_file' })
  ]])

  h.eq(read_approved, true)
  h.eq(insert_approved, true)
end

T["always()"]["handles multiple buffers independently"] = function()
  child.lua([[
    Approvals:always(1, { tool_name = 'read_file' })
    Approvals:always(2, { tool_name = 'insert_edit_into_file' })
  ]])

  local buf1_read = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'read_file' })
  ]])
  local buf1_insert = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'insert_edit_into_file' })
  ]])
  local buf2_read = child.lua([[
    return Approvals:is_approved(2, { tool_name = 'read_file' })
  ]])
  local buf2_insert = child.lua([[
    return Approvals:is_approved(2, { tool_name = 'insert_edit_into_file' })
  ]])

  h.eq(buf1_read, true)
  h.eq(buf1_insert, false)
  h.eq(buf2_read, false)
  h.eq(buf2_insert, true)
end

T["is_approved()"] = new_set()

T["is_approved()"]["returns false for non-existent buffer"] = function()
  local result = child.lua([[
    return Approvals:is_approved(999, { tool_name = 'read_file' })
  ]])

  h.eq(result, false)
end

T["is_approved()"]["returns false for non-approved tool"] = function()
  child.lua([[
    Approvals:always(1, { tool_name = 'read_file' })
  ]])

  local result = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'some_other_tool' })
  ]])

  h.eq(result, false)
end

T["is_approved()"]["returns true for approved tool"] = function()
  child.lua([[
    Approvals:always(1, { tool_name = 'read_file' })
  ]])

  local result = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'read_file' })
  ]])

  h.eq(result, true)
end

T["modes"] = new_set()

T["modes"]["auto approves a tool that is NOT protected"] = function()
  child.lua([[Approvals:set_mode(1, { mode = 'auto' })]])
  h.eq(true, child.lua([[return Approvals:is_approved(1, { tool_name = 'some_tool' })]]))
end

T["modes"]["auto DOES NOT approve a tool that IS protected"] = function()
  child.lua([[Approvals:set_mode(1, { mode = 'auto' })]])
  h.eq(false, child.lua([[return Approvals:is_approved(1, { tool_name = 'protected_tool' })]]))
end

T["modes"]["auto leaves cmd-approved tools to their own checks"] = function()
  child.lua([[Approvals:set_mode(1, { mode = 'auto' })]])
  h.eq(false, child.lua([[return Approvals:is_approved(1, { tool_name = 'run_command', cmd = 'git status' })]]))
end

T["modes"]["yolo approves a tool that IS protected"] = function()
  child.lua([[Approvals:set_mode(1, { mode = 'yolo' })]])
  h.eq(true, child.lua([[return Approvals:is_approved(1, { tool_name = 'protected_tool' })]]))
  h.eq(true, child.lua([[return Approvals:is_approved(1, { tool_name = 'run_command', cmd = 'rm -rf /' })]]))
end

T["modes"]["are buffer-specific"] = function()
  child.lua([[Approvals:set_mode(1, { mode = 'yolo' })]])
  h.eq(true, child.lua([[return Approvals:is_approved(1, { tool_name = 'any_tool' })]]))
  h.eq(false, child.lua([[return Approvals:is_approved(2, { tool_name = 'any_tool' })]]))
end

T["modes"]["toggle_yolo_mode() switches between ask and auto"] = function()
  local modes = child.lua([[
    local modes = {}
    Approvals:toggle_yolo_mode(1)
    table.insert(modes, Approvals:get_mode(1))
    Approvals:toggle_yolo_mode(1)
    table.insert(modes, Approvals:get_mode(1))
    return modes
  ]])
  h.eq({ "auto", "ask" }, modes)
end

T["is_safe_command()"] = new_set()

T["is_safe_command()"]["accepts a command on the safe list, with or without flags"] = function()
  h.eq(true, child.lua([[return Approvals.is_safe_command('git status')]]))
  h.eq(true, child.lua([[return Approvals.is_safe_command('git status --short')]]))
end

T["is_safe_command()"]["rejects a command that only shares a prefix with the safe list"] = function()
  h.eq(false, child.lua([[return Approvals.is_safe_command('lsblk')]]))
end

T["is_safe_command()"]["rejects a safe command that chains, nests or redirects"] = function()
  local results = child.lua([[
    local results = {}
    for _, cmd in ipairs({
      'ls; rm -rf /',
      'ls && rm -rf /',
      'ls | sh',
      'ls > files.txt',
      'ls $(rm -rf /)',
      'ls `rm -rf /`',
      'ls\nrm -rf /',
    }) do
      table.insert(results, Approvals.is_safe_command(cmd))
    end
    return results
  ]])
  h.eq({ false, false, false, false, false, false, false }, results)
end

T["reset()"] = new_set()

T["reset()"]["clears all approvals for buffer"] = function()
  child.lua([[
    Approvals:always(1, { tool_name = 'read_file' })
    Approvals:always(1, { tool_name = 'insert_edit_into_file' })
    Approvals:reset(1)
  ]])

  local result1 = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'read_file' })
  ]])
  local result2 = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'insert_edit_into_file' })
  ]])

  h.eq(result1, false)
  h.eq(result2, false)
end

T["reset()"]["clears the mode"] = function()
  child.lua([[
    Approvals:set_mode(1, { mode = 'yolo' })
    Approvals:reset(1)
  ]])

  local result = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'any_tool' })
  ]])

  h.eq(result, false)
end

T["reset()"]["only affects specified buffer"] = function()
  child.lua([[
    Approvals:always(1, { tool_name = 'read_file' })
    Approvals:always(2, { tool_name = 'read_file' })
    Approvals:reset(1)
  ]])

  local buf1_result = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'read_file' })
  ]])
  local buf2_result = child.lua([[
    return Approvals:is_approved(2, { tool_name = 'read_file' })
  ]])

  h.eq(buf1_result, false)
  h.eq(buf2_result, true)
end

T["reset()"]["handles non-existent buffer gracefully"] = function()
  local no_error = child.lua([[
    local ok = pcall(function()
      Approvals:reset(999)
    end)
    return ok
  ]])

  h.eq(no_error, true)
end

T["edge cases"] = new_set()

T["edge cases"]["maintains state across multiple operations"] = function()
  child.lua([[
    -- Add some tools
    Approvals:always(1, { tool_name = 'tool1' })
    Approvals:always(1, { tool_name = 'tool2' })

    -- Enable yolo mode
    Approvals:toggle_yolo_mode(1)

    -- Disable yolo mode
    Approvals:toggle_yolo_mode(1)
  ]])

  -- Original approvals should still exist
  local tool1 = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'tool1' })
  ]])
  local tool2 = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'tool2' })
  ]])
  -- But yolo mode should be off
  local unapproved = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'tool3' })
  ]])

  h.eq(tool1, true)
  h.eq(tool2, true)
  h.eq(unapproved, false)
end

T["command-level approvals"] = new_set()

T["command-level approvals"]["approves specific command for tool"] = function()
  child.lua([[
    -- Mock a tool with cmd approval requirement
    package.loaded['codecompanion.config'].interactions.chat.tools.run_command = {
      opts = {
        require_cmd_approval = true,
      },
    }

    Approvals:always(1, { tool_name = 'run_command', cmd = 'ls -la' })
  ]])

  local approved = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'run_command', cmd = 'ls -la' })
  ]])

  h.eq(approved, true)
end

T["command-level approvals"]["rejects unapproved command for same tool"] = function()
  child.lua([[
    package.loaded['codecompanion.config'].interactions.chat.tools.run_command = {
      opts = {
        require_cmd_approval = true,
      },
    }

    Approvals:always(1, { tool_name = 'run_command', cmd = 'ls -la' })
  ]])

  local approved = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'run_command', cmd = 'rm -rf /' })
  ]])

  h.eq(approved, false)
end

T["command-level approvals"]["allows multiple commands for same tool"] = function()
  child.lua([[
    package.loaded['codecompanion.config'].interactions.chat.tools.run_command = {
      opts = {
        require_cmd_approval = true,
      },
    }

    Approvals:always(1, { tool_name = 'run_command', cmd = 'ls -la' })
    Approvals:always(1, { tool_name = 'run_command', cmd = 'make test' })
  ]])

  local cmd1 = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'run_command', cmd = 'ls -la' })
  ]])
  local cmd2 = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'run_command', cmd = 'make test' })
  ]])
  local cmd3 = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'run_command', cmd = 'echo hello' })
  ]])

  h.eq(cmd1, true)
  h.eq(cmd2, true)
  h.eq(cmd3, false)
end

T["command-level approvals"]["handles tools without cmd requirement normally"] = function()
  child.lua([[
    -- Tool without require_cmd_approval
    package.loaded['codecompanion.config'].interactions.chat.tools.normal_tool = {
      opts = {},
    }

    Approvals:always(1, { tool_name = 'normal_tool' })
  ]])

  local approved = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'normal_tool' })
  ]])

  h.eq(approved, true)
end

T["command-level approvals"]["is buffer-specific for commands"] = function()
  child.lua([[
    package.loaded['codecompanion.config'].interactions.chat.tools.run_command = {
      opts = {
        require_cmd_approval = true,
      },
    }

    Approvals:always(1, { tool_name = 'run_command', cmd = 'ls -la' })
    Approvals:always(2, { tool_name = 'run_command', cmd = 'make test' })
  ]])

  local buf1_cmd1 = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'run_command', cmd = 'ls -la' })
  ]])
  local buf1_cmd2 = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'run_command', cmd = 'make test' })
  ]])
  local buf2_cmd1 = child.lua([[
    return Approvals:is_approved(2, { tool_name = 'run_command', cmd = 'ls -la' })
  ]])
  local buf2_cmd2 = child.lua([[
    return Approvals:is_approved(2, { tool_name = 'run_command', cmd = 'make test' })
  ]])

  h.eq(buf1_cmd1, true)
  h.eq(buf1_cmd2, false)
  h.eq(buf2_cmd1, false)
  h.eq(buf2_cmd2, true)
end

T["command-level approvals"]["resets command approvals with reset()"] = function()
  child.lua([[
    package.loaded['codecompanion.config'].interactions.chat.tools.run_command = {
      opts = {
        require_cmd_approval = true,
      },
    }

    Approvals:always(1, { tool_name = 'run_command', cmd = 'ls -la' })
    Approvals:reset(1)
  ]])

  local approved = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'run_command', cmd = 'ls -la' })
  ]])

  h.eq(approved, false)
end

T["command-level approvals"]["respects an always-accepted command for a protected tool in auto mode"] = function()
  child.lua([[
    package.loaded['codecompanion.config'].interactions.chat.tools.run_command = {
      opts = {
        protect = true,
        require_cmd_approval = true,
      },
    }

    Approvals:set_mode(1, { mode = 'auto' })
    Approvals:always(1, { tool_name = 'run_command', cmd = 'rake' })
  ]])

  local approved_cmd = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'run_command', cmd = 'rake' })
  ]])
  local other_cmd = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'run_command', cmd = 'rm -rf /' })
  ]])

  h.eq(approved_cmd, true)
  h.eq(other_cmd, false)
end

return T
