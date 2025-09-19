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
        opts = { requires_approval = true },
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

    -- Stub confirm to always choose "3 Cancel"
    local ui = require("codecompanion.utils.ui")
    ui.confirm = function(_) return 3 end

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

return T
