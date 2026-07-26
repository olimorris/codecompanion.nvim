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

---Queue a tool that is gated by the background safety check, in yolo mode, and
---replay a canned verdict from a stubbed judge
---@param verdict { safe: boolean, reason: string }
local function setup_yolo_mode_with_safety_check(verdict)
  child.lua(string.format(
    [[
    _G.executed = {}
    _G.prompted_with = nil

    -- The judge, stubbed so no request is made. Registered under a module path
    -- so it also covers `gates.safety_check.action` being configurable
    package.loaded["stub_judge"] = {
      request = function(_, request, callback)
        _G.judged_context = request.context
        callback(%s)
      end,
    }

    local cfg = {
      interactions = {
        background = {
          gates = { safety_check = { enabled = true, action = "stub_judge" } },
        },
        chat = {
          tools = {
            opts = { auto_submit_success = false, auto_submit_errors = false },
            dangerous = {
              enabled = true,
              opts = {
                allowed_in_yolo_mode = false,
                require_approval_before = true,
                require_cmd_approval = true,
                safety_check = true,
              },
              callback = function()
                return {
                  name = "dangerous",
                  cmds = {
                    function(self, args, opts)
                      table.insert(_G.executed, "dangerous")
                      opts.output_cb({ status = "success", data = "ran" })
                    end,
                  },
                  schema = {
                    type = "function",
                    ["function"] = {
                      name = "dangerous",
                      description = "A tool worth vetting",
                      parameters = { type = "object", properties = {} },
                    },
                  },
                  opts = {
                    allowed_in_yolo_mode = false,
                    require_approval_before = true,
                    require_cmd_approval = true,
                    safety_check = true,
                  },
                  output = {
                    cmd_string = function()
                      return "rm -rf /"
                    end,
                  },
                  gates = {
                    safety_context = function()
                      return "rm -rf /"
                    end,
                  },
                }
              end,
            },
          },
        },
      },
    }

    local chat, tools = h.setup_chat_buffer(cfg)
    _G.chat, _G.tools = chat, tools

    require("codecompanion.interactions.chat.tools.approvals"):toggle_yolo_mode(tools.bufnr)

    local ap = require("codecompanion.interactions.chat.helpers.approval_prompt")
    ap.request = function(_, opts)
      _G.prompted_with = opts.prompt
    end

    _G.tools:execute(_G.chat, { { ["function"] = { name = "dangerous", arguments = "{}" } } })
    vim.wait(250)
  ]],
    vim.inspect(verdict)
  ))
end

T["safe verdict runs the tool without prompting"] = function()
  setup_yolo_mode_with_safety_check({ safe = true, reason = "reads only" })

  h.eq({ "dangerous" }, child.lua_get("_G.executed"))
  h.eq(vim.NIL, child.lua_get("_G.prompted_with"))
  h.eq("rm -rf /", child.lua_get("_G.judged_context"))
end

T["unsafe verdict prompts with the judge's reason instead of running"] = function()
  setup_yolo_mode_with_safety_check({ safe = false, reason = "deletes the filesystem" })

  h.eq({}, child.lua_get("_G.executed"))
  h.eq('Run the "dangerous" tool?\nJudge: _"deletes the filesystem"_', child.lua_get("_G.prompted_with"))
end

return T
