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
          tools = {},
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

    _G.submitted = 0
    local submit = chat.submit
    chat.submit = function(self, opts)
      _G.submitted = _G.submitted + 1
      return submit(self, opts)
    end

    if _G.queue_workflow_prompt then
      chat.subscribers:subscribe({ data = { opts = { auto_submit = true } }, callback = function() end })
    end

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

T["rejecting a tool continues the agent loop"] = function()
  setup_with_tools_and_approval_stub(1, "Reject")

  h.eq(child.lua_get("_G.submitted"), 1)
end

T["cancelling a tool ENDS the agent loop"] = function()
  setup_with_tools_and_approval_stub(2, "Cancel")

  h.eq(child.lua_get("_G.executed or {}"), {})
  h.eq(child.lua_get("_G.submitted"), 0)
end

T["cancelling a tool DOES NOT submit a queued workflow prompt"] = function()
  child.lua([[_G.queue_workflow_prompt = true]])
  setup_with_tools_and_approval_stub(1, "Cancel")
  child.lua([[vim.wait(700)]])

  h.eq(child.lua_get("_G.submitted"), 0)
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

---Queue a tool in auto mode, with the judge stubbed to reply with a canned verdict
---@param opts { verdict?: { safe: boolean, reason: string }, protect?: boolean, is_safe?: boolean }
local function setup_auto_mode(opts)
  local verdict = opts.verdict or { safe = false, reason = "not judged" }
  child.lua(
    string.format(
      [[
    _G.executed = {}
    _G.prompted_with = nil
    _G.judged_context = nil

    -- The judge, stubbed so no request is made. Registered under a module path
    -- so it also covers `gates.judge.action` being configurable
    package.loaded["stub_judge"] = {
      request = function(_, request, callback)
        _G.judged_context = request.context
        callback(%s)
      end,
    }

    local cfg = {
      interactions = {
        background = {
          gates = { judge = { enabled = true, action = "stub_judge" } },
        },
        chat = {
          tools = {
            dangerous = {
              enabled = true,
              opts = {
                judge = true,
                protect = %s,
                require_approval_before = true,
                require_cmd_approval = true,
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
                    judge = true,
                    protect = %s,
                    require_approval_before = true,
                    require_cmd_approval = true,
                  },
                  output = {
                    cmd_string = function()
                      return "rm -rf /"
                    end,
                  },
                  gates = {
                    is_safe = function()
                      return %s
                    end,
                    judge_context = function()
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

    require("codecompanion.interactions.chat.tools.approvals"):set_mode(tools.bufnr, { mode = "auto" })

    local ap = require("codecompanion.interactions.chat.helpers.approval_prompt")
    ap.request = function(_, opts)
      _G.prompted_with = opts.prompt
    end

    _G.tools:execute(_G.chat, { { ["function"] = { name = "dangerous", arguments = "{}" } } })
    vim.wait(250)
  ]],
      vim.inspect(verdict),
      tostring(opts.protect == true),
      tostring(opts.protect == true),
      tostring(opts.is_safe == true)
    )
  )
end

T["safe verdict runs the tool without prompting"] = function()
  setup_auto_mode({ verdict = { safe = true, reason = "reads only" } })

  h.eq({ "dangerous" }, child.lua_get("_G.executed"))
  h.eq(vim.NIL, child.lua_get("_G.prompted_with"))
  h.eq("rm -rf /", child.lua_get("_G.judged_context"))
end

T["unsafe verdict prompts with the judge's reason instead of running"] = function()
  setup_auto_mode({ verdict = { safe = false, reason = "deletes the filesystem" } })

  h.eq({}, child.lua_get("_G.executed"))
  h.eq('Run the "dangerous" tool?\nJudge: _"deletes the filesystem"_', child.lua_get("_G.prompted_with"))
end

T["safe command runs without judging or prompting"] = function()
  setup_auto_mode({ is_safe = true })

  h.eq({ "dangerous" }, child.lua_get("_G.executed"))
  h.eq(vim.NIL, child.lua_get("_G.judged_context"))
  h.eq(vim.NIL, child.lua_get("_G.prompted_with"))
end

T["protected tool prompts without judging, even for a safe command"] = function()
  setup_auto_mode({ protect = true, is_safe = true, verdict = { safe = true, reason = "reads only" } })

  h.eq({}, child.lua_get("_G.executed"))
  h.eq(vim.NIL, child.lua_get("_G.judged_context"))
  h.eq('Run the "dangerous" tool?', child.lua_get("_G.prompted_with"))
end

return T
