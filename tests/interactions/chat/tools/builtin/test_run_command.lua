local h = require("tests.helpers")

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

T["run_command tool"] = function()
  child.lua([[
    --require("tests.log")
    local tool = {
      {
        ["function"] = {
          name = "run_command",
          arguments = '{"cmd": "echo hello world"}',
        },
      },
    }
    tools:execute(chat, tool)
    vim.wait(200)
  ]])

  h.expect_screenshot(child.get_screenshot())
end

T["run_command tool times out a long running command"] = function()
  child.lua([[
    local cfg = {
      interactions = {
        chat = {
          tools = {
            run_command = { opts = { timeout = 100 } }
          }
        }
      }
    }
    chat, tools = h.setup_chat_buffer(cfg)

    local tool = {
      {
        ["function"] = {
          name = "run_command",
          arguments = '{"cmd": "sleep 2"}',
        },
      },
    }
    tools:execute(chat, tool)
    vim.wait(500)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("timed out", output)
end

T["stopping the chat kills a running command"] = function()
  child.lua([[
    _G.marker = vim.fn.tempname()

    local tool = {
      {
        ["function"] = {
          name = "run_command",
          arguments = string.format('{"cmd": "sleep 1 && touch %s"}', _G.marker),
        },
      },
    }
    tools:execute(chat, tool)
    vim.wait(200)

    _G.running = chat.tool_orchestrator ~= nil and chat.tool_orchestrator.current_job ~= nil
    chat:stop()
    vim.wait(1500)
  ]])

  h.eq(true, child.lua_get("_G.running"))
  h.eq(0, child.lua_get("vim.fn.filereadable(_G.marker)"))
  h.eq(vim.NIL, child.lua_get("chat.tool_orchestrator"))
  h.expect_contains("cancelled", child.lua_get("chat.messages[#chat.messages].content"))
end

T["Windows"] = new_set()

T["Windows"]["run_command handles Windows pipe command with empty string argument"] = function()
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

    -- Use the actual run_command tool
    local cfg = {
      interactions = {
        chat = {
          tools = {
            run_command = { enabled = true }
          }
        }
      }
    }

    local chat, tools = h.setup_chat_buffer(cfg)
    _G.chat, _G.tools, _G.command_results = chat, tools, command_results

    -- Simulate LLM calling run_command with pipe and find command that has empty string argument
    local calls = {
      {
        ["function"] = {
          name = "run_command",
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
