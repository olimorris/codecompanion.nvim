local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")
        _G.cancelled = {}
      ]])
    end,
    post_case = function()
      child.lua([[
        _G.chat, _G.tools, _G.cancelled = nil, nil, nil
      ]])
    end,
    post_once = child.stop,
  },
})

local function setup_with_tools_and_cancel_stub(n_tools)
  child.lua(string.format(
    [[
    -- Build a minimal config with custom tools that require approval
    local cfg = {
      strategies = {
        chat = {
          tools = {
            opts = {
              auto_submit_success = false,
              auto_submit_errors = false,
            },
          },
        },
      },
    }

    local function make_tool(n)
      return {
        name = n,
        cmds = {
          function(self, args, input, cb)
            -- Should not run when 'Cancel' is selected, but return success if it does
            cb({ status = "success", data = n .. "_ran" })
          end,
        },
        schema = {
          type = "function",
          ["function"] = {
            name = n,
            description = "Test tool " .. n,
            parameters = { type = "object", properties = {} },
          },
        },
        opts = { require_approval_before = true },
        output = {
          cancelled = function(self, tools, _)
            _G.cancelled = _G.cancelled or {}
            table.insert(_G.cancelled, self.name)
            tools.chat:add_tool_output(self, "cancelled:" .. self.name)
          end,
        },
      }
    end

    -- Register tools in test config
    cfg.strategies.chat.tools.t1 = { callback = function() return make_tool("t1") end, enabled = true }
    if %d >= 2 then
      cfg.strategies.chat.tools.t2 = { callback = function() return make_tool("t2") end, enabled = true }
    end
    if %d >= 3 then
      cfg.strategies.chat.tools.t3 = { callback = function() return make_tool("t3") end, enabled = true }
    end

    -- Create chat and tools
    local chat, tools = h.setup_chat_buffer(cfg)
    _G.chat, _G.tools = chat, tools

    -- Stub confirm to always choose "4 Cancel"
    local ui = require("codecompanion.utils.ui")
    ui.confirm = function(_) return 4 end

    -- Build tool calls
    local calls = {
      { ["function"] = { name = "t1", arguments = "{}" } },
    }
    if %d >= 2 then
      table.insert(calls, { ["function"] = { name = "t2", arguments = "{}" } })
    end
    if %d >= 3 then
      table.insert(calls, { ["function"] = { name = "t3", arguments = "{}" } })
    end

    -- Execute
    _G.tools:execute(_G.chat, calls)
    vim.wait(250)
  ]],
    n_tools,
    n_tools,
    n_tools,
    n_tools
  ))
end

T["cancels all queued tools when user selects cancel"] = function()
  setup_with_tools_and_cancel_stub(3)

  local cancelled = child.lua_get("_G.cancelled or {}")
  h.eq(cancelled, { "t1", "t2", "t3" })

  -- Ensure chat received cancellation outputs for each tool
  local all = child.lua([[
    local msgs = {}
    for _, m in ipairs(_G.chat.messages or {}) do
      if type(m.content) == "string" then table.insert(msgs, m.content) end
    end
    return table.concat(msgs, "\n")
  ]])
  h.expect_contains("cancelled:t1", all)
  h.expect_contains("cancelled:t2", all)
  h.expect_contains("cancelled:t3", all)
end

T["cancels current tool when it is the only one"] = function()
  setup_with_tools_and_cancel_stub(1)

  local cancelled = child.lua_get("_G.cancelled or {}")
  h.eq(cancelled, { "t1" })

  local all = child.lua([[
    local msgs = {}
    for _, m in ipairs(_G.chat.messages or {}) do
      if type(m.content) == "string" then table.insert(msgs, m.content) end
    end
    return table.concat(msgs, "\n")
  ]])
  h.expect_contains("cancelled:t1", all)
end

T["cmd_runner handles Windows pipe command with empty string argument"] = function()
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
      strategies = {
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

  -- Parse output lines and trim leading/trailing empty lines
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
