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
        chat, tools = h.setup_chat_buffer()
        _G.cancelled = {}
      ]])
    end,
    post_case = function()
      child.lua([[
      _G.cancelled = nil
      h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

local function setup_with_tools_and_approval_stub(n_tools, choice_label)
  child.lua(string.format(
    [[
    -- Build a minimal config with custom tools that require approval
    local cfg = {
      interactions = {
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

    _G.executed = {}

    local function make_tool(n)
      return {
        name = n,
        cmds = {
          function(self, args, opts)
            _G.executed = _G.executed or {}
            table.insert(_G.executed, n)
            opts.output_cb({ status = "success", data = n .. "_ran" })
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
      }
    end

    -- Register tools in test config
    cfg.interactions.chat.tools.t1 = { callback = function() return make_tool("t1") end, enabled = true }
    if %d >= 2 then
      cfg.interactions.chat.tools.t2 = { callback = function() return make_tool("t2") end, enabled = true }
    end
    if %d >= 3 then
      cfg.interactions.chat.tools.t3 = { callback = function() return make_tool("t3") end, enabled = true }
    end

    -- Create chat and tools
    local chat, tools = h.setup_chat_buffer(cfg)
    _G.chat, _G.tools = chat, tools

    -- Stub approval_prompt to auto-select a choice by label
    local ap = require("codecompanion.interactions.chat.helpers.approval_prompt")
    ap.request = function(_, opts)
      for _, choice in ipairs(opts.choices) do
        if choice.label == %q then
          choice.callback()
          return
        end
      end
    end

    -- Stub vim.ui.input for rejection reason
    vim.ui.input = function(_, cb)
      cb("test rejection")
    end

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
    choice_label,
    n_tools,
    n_tools
  ))
end

T["approves all queued tools when user selects approve"] = function()
  setup_with_tools_and_approval_stub(3, "Accept")

  local executed = child.lua_get("_G.executed or {}")
  h.eq(executed, { "t1", "t2", "t3" })
end

T["approves single tool when user selects approve"] = function()
  setup_with_tools_and_approval_stub(1, "Accept")

  local executed = child.lua_get("_G.executed or {}")
  h.eq(executed, { "t1" })
end

T["rejects all queued tools when user selects reject"] = function()
  setup_with_tools_and_approval_stub(3, "Reject")

  -- No tools should have executed
  local executed = child.lua_get("_G.executed or {}")
  h.eq(executed, {})
end

T["tools only receive output that relates to their execution"] = function()
  child.lua([[
    --require("tests.log")

    local tool_call = {
      {
        ["function"] = {
          name = "func",
          arguments = { data = "Data 1" },
        },
      },
      {
        ["function"] = {
          name = "func",
          arguments = { data = "Data 2" },
        },
      },
    }
    tools:execute(chat, tool_call)
  ]])

  local output = child.lua_get([[_G._test_success_stdout]])
  h.eq({ "Data 2" }, output)
end

return T
