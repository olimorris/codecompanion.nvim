local h = require("tests.helpers")
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        defaults = require("codecompanion.interactions.chat.acp.defaults")

        ---Build a fake connection with `set_config_option` recording calls
        function fake_connection(config_options)
          local calls = {}
          local conn = {
            _config_options = config_options or {},
            get_config_options = function(self)
              return self._config_options
            end,
            set_config_option = function(self, config_id, value)
              table.insert(calls, { config_id = config_id, value = value })
              return true
            end,
          }
          return conn, calls
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["ACP Defaults"] = new_set()

T["ACP Defaults"]["applies a session_config_options entry via exact value match"] = function()
  local calls = child.lua([[
    local conn, calls = fake_connection({
      {
        type = "select", id = "mode", name = "Mode", category = "mode",
        currentValue = "default",
        options = { { value = "default", name = "Default" }, { value = "auto", name = "Auto" } },
      },
    })
    defaults.apply({ defaults = { session_config_options = { mode = "auto" } } }, conn)
    return calls
  ]])

  h.eq(1, #calls)
  h.eq("mode", calls[1].config_id)
  h.eq("auto", calls[1].value)
end

T["ACP Defaults"]["does not substring-match name (avoids accidental matches like `low` -> `Lowest`)"] = function()
  local calls = child.lua([[
    local conn, calls = fake_connection({
      {
        type = "select", id = "effort", name = "Effort", category = "thought_level",
        currentValue = "medium",
        options = { { value = "lowest", name = "Lowest" }, { value = "medium", name = "Medium" } },
      },
    })
    defaults.apply({ defaults = { session_config_options = { thought_level = "low" } } }, conn)
    return calls
  ]])

  h.eq(0, #calls)
end

T["ACP Defaults"]["case-insensitively matches against option name when value lookup misses"] = function()
  local calls = child.lua([[
    local conn, calls = fake_connection({
      {
        type = "select", id = "model", name = "Model", category = "model",
        currentValue = "default",
        options = { { value = "haiku", name = "Haiku" }, { value = "opus", name = "Opus" } },
      },
    })
    -- Capitalised friendly name, not the value
    defaults.apply({ defaults = { session_config_options = { model = "Haiku" } } }, conn)
    return calls
  ]])

  h.eq(1, #calls)
  h.eq("model", calls[1].config_id)
  h.eq("haiku", calls[1].value)
end

T["ACP Defaults"]["uses opt.id when it differs from the category"] = function()
  -- Claude Code advertises category="thought_level", id="effort"
  local calls = child.lua([[
    local conn, calls = fake_connection({
      {
        type = "select", id = "effort", name = "Effort", category = "thought_level",
        currentValue = "medium",
        options = { { value = "low", name = "Low" }, { value = "medium", name = "Medium" } },
      },
    })
    defaults.apply({ defaults = { session_config_options = { thought_level = "low" } } }, conn)
    return calls
  ]])

  h.eq(1, #calls)
  h.eq("effort", calls[1].config_id)
  h.eq("low", calls[1].value)
end

T["ACP Defaults"]["applies model first so dependent options resolve against the right model"] = function()
  local calls = child.lua([[
    local conn, calls = fake_connection({
      {
        type = "select", id = "model", name = "Model", category = "model",
        currentValue = "default",
        options = { { value = "default", name = "Default" }, { value = "haiku", name = "Haiku" } },
      },
      {
        type = "select", id = "effort", name = "Effort", category = "thought_level",
        currentValue = "medium",
        options = { { value = "low", name = "Low" }, { value = "medium", name = "Medium" } },
      },
    })
    defaults.apply({
      defaults = { session_config_options = { thought_level = "low", model = "haiku" } },
    }, conn)
    return calls
  ]])

  h.eq(2, #calls)
  h.eq("model", calls[1].config_id)
  h.eq("effort", calls[2].config_id)
end

T["ACP Defaults"]["skips when desired value already matches currentValue"] = function()
  local calls = child.lua([[
    local conn, calls = fake_connection({
      {
        type = "select", id = "mode", name = "Mode", category = "mode",
        currentValue = "auto",
        options = { { value = "default", name = "Default" }, { value = "auto", name = "Auto" } },
      },
    })
    defaults.apply({ defaults = { session_config_options = { mode = "auto" } } }, conn)
    return calls
  ]])

  h.eq(0, #calls)
end

T["ACP Defaults"]["warns and skips when category is not advertised"] = function()
  local calls = child.lua([[
    local conn, calls = fake_connection({
      {
        type = "select", id = "mode", name = "Mode", category = "mode",
        currentValue = "default",
        options = { { value = "default", name = "Default" } },
      },
    })
    defaults.apply({
      defaults = { session_config_options = { thought_level = "low" } },
    }, conn)
    return calls
  ]])

  h.eq(0, #calls)
end

T["ACP Defaults"]["warns and skips when value is not in the option"] = function()
  local calls = child.lua([[
    local conn, calls = fake_connection({
      {
        type = "select", id = "mode", name = "Mode", category = "mode",
        currentValue = "default",
        options = { { value = "default", name = "Default" } },
      },
    })
    defaults.apply({ defaults = { session_config_options = { mode = "auto" } } }, conn)
    return calls
  ]])

  h.eq(0, #calls)
end

T["ACP Defaults"]["does nothing when adapter has no defaults"] = function()
  local calls = child.lua([[
    local conn, calls = fake_connection({
      {
        type = "select", id = "mode", name = "Mode", category = "mode",
        currentValue = "default",
        options = { { value = "default", name = "Default" } },
      },
    })
    defaults.apply({ defaults = {} }, conn)
    return calls
  ]])

  h.eq(0, #calls)
end

T["ACP Defaults"]["does nothing when the connection has no config options yet"] = function()
  local calls = child.lua([[
    local conn, calls = fake_connection({})
    defaults.apply({ defaults = { session_config_options = { mode = "auto" } } }, conn)
    return calls
  ]])

  h.eq(0, #calls)
end

T["ACP Defaults"]["re-reads config options between iterations so changes from set_config_option are visible"] = function()
  -- Simulates the real Claude Code flow: setting model swaps the effort
  -- option's available values (Haiku has different effort levels than Sonnet).
  -- defaults.apply must resolve `effort=low` against the *post-model-change*
  -- snapshot, not the snapshot it saw before applying model.
  local result = child.lua([[
    local calls = {}
    local options_before = {
      {
        type = "select", id = "model", name = "Model", category = "model",
        currentValue = "default",
        options = { { value = "default", name = "Default" }, { value = "haiku", name = "Haiku" } },
      },
      {
        type = "select", id = "effort", name = "Effort", category = "thought_level",
        currentValue = "medium",
        options = { { value = "low", name = "Low" }, { value = "medium", name = "Medium" } },
      },
    }
    local options_after_model = {
      {
        type = "select", id = "model", name = "Model", category = "model",
        currentValue = "haiku",
        options = { { value = "default", name = "Default" }, { value = "haiku", name = "Haiku" } },
      },
      {
        type = "select", id = "effort", name = "Effort", category = "thought_level",
        currentValue = "minimal",
        options = { { value = "minimal", name = "Minimal" }, { value = "standard", name = "Standard" } },
      },
    }

    local conn = {
      _options = options_before,
      get_config_options = function(self) return self._options end,
      set_config_option = function(self, config_id, value)
        table.insert(calls, { config_id = config_id, value = value })
        if config_id == "model" then
          -- The agent advertises a fresh effort option list for the new model
          self._options = options_after_model
        end
        return true
      end,
    }

    defaults.apply({
      defaults = { session_config_options = { model = "haiku", thought_level = "low" } },
    }, conn)
    return calls
  ]])

  -- Only model is applied; "low" isn't in the post-change effort list so it's skipped with a warning
  h.eq(1, #result)
  h.eq("model", result[1].config_id)
  h.eq("haiku", result[1].value)
end

T["ACP Defaults"]["respects legacy top-level model field"] = function()
  local calls = child.lua([[
    local conn, calls = fake_connection({
      {
        type = "select", id = "model", name = "Model", category = "model",
        currentValue = "default",
        options = { { value = "default", name = "Default" }, { value = "haiku", name = "Haiku" } },
      },
    })
    defaults.apply({ defaults = { model = "haiku" } }, conn)
    return calls
  ]])

  h.eq(1, #calls)
  h.eq("model", calls[1].config_id)
  h.eq("haiku", calls[1].value)
end

return T
