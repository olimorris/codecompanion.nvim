local h = require("tests.helpers")

local expect = MiniTest.expect
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        chat, tools = h.setup_chat_buffer()

        _G.output = nil
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["cmd_runner tool"] = function()
  child.lua([[
    --require("tests.log")
    local tool = {
      {
        ["function"] = {
          name = "cmd_runner",
          arguments = '{"cmd": "echo hello world"}',
        },
      },
    }
    tools:execute(chat, tool)
    vim.wait(200)
  ]])

  expect.reference_screenshot(child.get_screenshot())
end

T["Windows"] = new_set()

T["Windows"]["cmd_runner handles Windows pipe command with empty string argument"] = function()
  -- Skip on non-Windows systems
  if vim.fn.has("win32") == 0 then
    MiniTest.skip("Skipping Windows specific test")
  end

  child.lua([[
    local h = require("tests.helpers")

    -- Mock vim.system to execute real command but not call out_cb
    local command_results = {}
    local original_system = vim.system
    vim.system = function(args, opts, callback)
      -- Execute the real command but capture the result instead of calling the callback
      original_system(args, opts, function(result)
        table.insert(command_results, result)
        -- Don't call the original callback - we'll handle the result in the test
      end)
    end

    -- Use the actual cmd_runner tool
    local cfg = {
      interactions = {
        chat = {
          tools = {
            cmd_runner = { enabled = true }
          }
        }
      }
    }

    local chat, tools = h.setup_chat_buffer(cfg)
    _G.chat, _G.tools, _G.command_results = chat, tools, command_results

    -- Simulate LLM calling cmd_runner with pipe and find command that has empty string argument
    local calls = {
      {
        ["function"] = {
          name = "cmd_runner",
          -- Use full path to find.exe, since I know developers
          -- who have added a POSIX find.exe earlier in their PATH
          -- Using find.exe to explicitly pass in an empty argument
          -- which needs to make it AS an empty argument and not
          -- overly escaped or overly quoted strings
          arguments = '{"cmd": "echo hello there | %windir%\\\\System32\\\\find.exe /c /v \\"\\"", "flag": null}'
        }
      },
    }

    _G.tools:execute(_G.chat, calls)
    vim.wait(1000) -- Give more time for the real command to execute

    -- Restore original vim.system
    vim.system = original_system
  ]])

  -- Verify the actual command execution was successful and produced expected output
  local command_results = child.lua_get("_G.command_results")
  h.eq(#command_results, 1)

  local result = command_results[1]
  h.eq(result.code, 0) -- Command should succeed

  local lines = vim.split(result.stdout, "\r?\n", { plain = false })
  -- Remove leading empty lines
  while #lines > 0 and (lines[1] == "" or lines[1] == "\r") do
    table.remove(lines, 1)
  end
  -- Remove trailing empty lines
  while #lines > 0 and (lines[#lines] == "" or lines[#lines] == "\r") do
    table.remove(lines, #lines)
  end

  h.eq(lines, { "1" })
end

return T
