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
                restricted_tool = {
                  opts = {
                    allowed_in_yolo_mode = false,
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

T["yolo mode"] = new_set()

T["yolo mode"]["toggle_yolo_mode() enables yolo mode"] = function()
  child.lua([[
    Approvals:toggle_yolo_mode(1)
  ]])

  -- Any tool should be approved in yolo mode
  local result = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'any_random_tool' })
  ]])

  h.eq(result, true)
end

T["yolo mode"]["toggle_yolo_mode() disables yolo mode when called twice"] = function()
  child.lua([[
    Approvals:toggle_yolo_mode(1)
    Approvals:toggle_yolo_mode(1)
  ]])

  local result = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'unapproved_tool' })
  ]])

  h.eq(result, false)
end

T["yolo mode"]["approves all tools by default"] = function()
  child.lua([[
    Approvals:toggle_yolo_mode(1)
  ]])

  local tool1 = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'some_tool' })
  ]])
  local tool2 = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'another_tool' })
  ]])

  h.eq(tool1, true)
  h.eq(tool2, true)
end

T["yolo mode"]["respects allowed_in_yolo_mode = false"] = function()
  child.lua([[
    -- Ensure the config is properly set before toggling yolo mode
    package.loaded['codecompanion.config'].interactions.chat.tools.restricted_tool = {
      opts = {
        allowed_in_yolo_mode = false,
      },
    }

    Approvals:toggle_yolo_mode(1)
  ]])

  -- Debug: check what the config actually contains
  local config_check = child.lua([[
    local cfg = require('codecompanion.config')
    local tool_cfg = cfg.interactions.chat.tools.restricted_tool
    return {
      exists = tool_cfg ~= nil,
      has_opts = tool_cfg and tool_cfg.opts ~= nil,
      allowed_value = tool_cfg and tool_cfg.opts and tool_cfg.opts.allowed_in_yolo_mode
    }
  ]])

  local restricted = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'restricted_tool' })
  ]])
  local allowed = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'some_tool' })
  ]])

  h.eq(restricted, false)
  h.eq(allowed, true)
end

--TODO: Should not take precedence over individual approvals
T["yolo mode"]["takes precedence over individual approvals"] = function()
  child.lua([[
    Approvals:always(1, { tool_name = 'read_file' })
    Approvals:toggle_yolo_mode(1)
  ]])

  -- Should approve tools that weren't explicitly added
  local result = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'some_other_tool' })
  ]])

  h.eq(result, true)
end

T["yolo mode"]["is buffer-specific"] = function()
  child.lua([[
    Approvals:toggle_yolo_mode(1)
  ]])

  local buf1_result = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'any_tool' })
  ]])
  local buf2_result = child.lua([[
    return Approvals:is_approved(2, { tool_name = 'any_tool' })
  ]])

  h.eq(buf1_result, true)
  h.eq(buf2_result, false)
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

T["reset()"]["clears yolo mode"] = function()
  child.lua([[
    Approvals:toggle_yolo_mode(1)
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

T["command-level approvals"]["yolo mode overrides cmd approval requirement"] = function()
  child.lua([[
    package.loaded['codecompanion.config'].interactions.chat.tools.run_command = {
      opts = {
        require_cmd_approval = true,
      },
    }

    Approvals:toggle_yolo_mode(1)
  ]])

  local approved = child.lua([[
    return Approvals:is_approved(1, { tool_name = 'run_command', cmd = 'any command' })
  ]])

  h.eq(approved, true)
end

return T
