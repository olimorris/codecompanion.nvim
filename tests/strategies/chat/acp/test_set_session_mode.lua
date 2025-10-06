local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        local cfg = require("codecompanion.config")
        cfg.strategies = cfg.strategies or {}
        cfg.strategies.chat = cfg.strategies.chat or {}
        cfg.strategies.chat.opts = cfg.strategies.chat.opts or {}
        cfg.strategies.chat.opts.wait_timeout = 1234
      ]])
    end,
    post_case = function()
      child.lua([[
        package.loaded["codecompanion.strategies.chat.acp.set_session_mode"] = nil
        package.loaded["codecompanion.acp"] = nil
        package.loaded["codecompanion.acp.init"] = nil
      ]])
    end,
    post_once = child.stop,
  },
})

T["show uses vim.ui.select with current mode default and forwards selection"] = function()
  local result = child.lua([[ 
    local orig_select = vim.ui.select
    local captured = {}

    vim.ui.select = function(entries, opts, on_choice)
      captured.entries = entries
      captured.opts = opts
      on_choice(entries[2], 2)
    end

    local received = {}
    require("codecompanion.strategies.chat.acp.set_session_mode").show(nil, {
      available_modes = {
        { id = "mode-a", name = "Alpha" },
        { id = "mode-b", name = "Beta" },
      },
      current_mode_id = "mode-b",
      on_select = function(mode_id, mode, idx)
        received.mode_id = mode_id
        received.mode = mode
        received.idx = idx
      end,
    })

    vim.ui.select = orig_select

    return {
      prompt = captured.opts and captured.opts.prompt,
      default_index = captured.opts and captured.opts.default,
      entry_count = captured.entries and #captured.entries or 0,
      label_current = captured.entries and captured.entries[2] and captured.entries[2].label,
      selected_mode_id = received.mode_id,
      selected_mode_name = received.mode and received.mode.name or nil,
      selected_index = received.idx,
    }
  ]])

  h.eq("Session mode: Set Session Mode?", result.prompt)
  h.eq(2, result.default_index)
  h.eq(2, result.entry_count)
  h.eq("Beta (current)", result.label_current)
  h.eq("mode-b", result.selected_mode_id)
  h.eq("Beta", result.selected_mode_name)
  h.eq(2, result.selected_index)
end

T["connection set_session_mode schedules RPC with chosen mode"] = function()
  local result = child.lua([[ 
    local Connection = require("codecompanion.acp")
    local conn = Connection.new({ adapter = { type = "acp" } })
    conn.session_id = "session-1"
    conn.chat = {}
    conn.modes = {
      availableModes = {
        { id = "mode-a", name = "Alpha" },
        { id = "mode-b", name = "Beta" },
      },
      currentModeId = "mode-a",
      currentMode = { id = "mode-a", name = "Alpha" },
    }

    conn.methods.schedule_wrap = function(fn)
      return fn
    end

    local rpc_calls = {}
    conn.send_rpc_request = function(self, method, payload)
      table.insert(rpc_calls, { method = method, payload = payload })
      return {}
    end

    local captured_opts
    local orig_select = vim.ui.select
    vim.ui.select = function(entries, opts, on_choice)
      captured_opts = opts
      on_choice(entries[2], 2)
    end

    local ok = conn:set_session_mode(conn.chat)

    vim.ui.select = orig_select

    return {
      ok = ok,
      rpc = rpc_calls[1],
      current_mode_id = conn.modes.currentModeId,
      current_mode_name = conn.modes.currentMode and conn.modes.currentMode.name or nil,
      select_default = captured_opts and captured_opts.default,
    }
  ]])

  h.eq(true, result.ok)
  h.eq("session/set_mode", result.rpc and result.rpc.method)
  h.eq({ sessionId = "session-1", modeId = "mode-b" }, result.rpc and result.rpc.payload)
  h.eq("mode-b", result.current_mode_id)
  h.eq("Beta", result.current_mode_name)
  h.eq(1, result.select_default)
end

T["connection set_session_mode handles cancellation without RPC"] = function()
  local result = child.lua([[ 
    local Connection = require("codecompanion.acp")
    local conn = Connection.new({ adapter = { type = "acp" } })
    conn.session_id = "session-1"
    conn.chat = {}
    conn.modes = {
      availableModes = {
        { id = "mode-a", name = "Alpha" },
        { id = "mode-b", name = "Beta" },
      },
      currentModeId = "mode-a",
      currentMode = { id = "mode-a", name = "Alpha" },
    }

    conn.methods.schedule_wrap = function(fn)
      return fn
    end

    local rpc_calls = {}
    conn.send_rpc_request = function(self, method, payload)
      table.insert(rpc_calls, { method = method, payload = payload })
      return {}
    end

    local orig_select = vim.ui.select
    vim.ui.select = function(_entries, _opts, on_choice)
      on_choice(nil, nil)
    end

    local ok = conn:set_session_mode(conn.chat)

    vim.ui.select = orig_select

    return {
      ok = ok,
      rpc_count = #rpc_calls,
      current_mode_id = conn.modes.currentModeId,
    }
  ]])

  h.eq(true, result.ok)
  h.eq(0, result.rpc_count)
  h.eq("mode-a", result.current_mode_id)
end

return T
