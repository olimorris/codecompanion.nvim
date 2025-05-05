local new_set = MiniTest.new_set
local h = require("tests.helpers")

local adapters = require("codecompanion.adapters")
local client_mod = require("codecompanion.http")
local log = require("codecompanion.utils.log")
local web_search = require("codecompanion.strategies.chat.agents.tools.web_search")

local T = new_set({
  hooks = {
    pre_case = function()
      T._resolve_orig = adapters.resolve
      adapters.resolve = function(adapter)
        return adapter
      end

      T._log_err_orig = log.error
      log.error = function() end

      T._client_new_orig = client_mod.new
      client_mod.new = function(_)
        return {
          request = function(_, _, _) end,
        }
      end
    end,

    post_case = function()
      adapters.resolve = T._resolve_orig
      log.error = T._log_err_orig
      client_mod.new = T._client_new_orig

      package.loaded["codecompanion.adapters.non_llm.valid_adapter"] = nil
    end,
  },
})

local function call_tool(self, args)
  local out
  web_search.cmds[1](self, args, nil, function(res)
    out = res
  end)
  return out
end

T["error when no opts"] = function()
  local got = call_tool({ tool = {} }, { query = "q" })
  h.eq(got.status, "error")
end

T["error when args nil"] = function()
  local self = { tool = { opts = { adapter = "valid_adapter", opts = {} } } }
  local got = call_tool(self, nil)
  h.eq(got.status, "error")
end

T["error when require adapter fails"] = function()
  local self = { tool = { opts = { adapter = "invalid", opts = {} } } }
  local got = call_tool(self, { query = "q" })
  h.eq(got.status, "error")
end

T["error when resolve returns nil"] = function()
  adapters.resolve = function()
    return nil
  end
  local self = { tool = { opts = { adapter = "valid_adapter", opts = {} } } }
  local got = call_tool(self, { query = "q" })
  h.eq(got.status, "error")

  adapters.resolve = T._resolve_orig
end

return T
