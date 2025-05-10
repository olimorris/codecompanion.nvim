local new_set = MiniTest.new_set
local h = require("tests.helpers")

local client_mod = require("codecompanion.http")
local log = require("codecompanion.utils.log")
local non_llm_adapters = require("codecompanion.adapters.non_llm")
local web_search = require("codecompanion.strategies.chat.agents.tools.web_search")

local T = new_set({
  hooks = {
    pre_case = function()
      T._resolve_orig = non_llm_adapters.resolve
      non_llm_adapters.resolve = function(adapter)
        if adapter == "invalid" then
          return nil
        end
        return {}
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
      non_llm_adapters.resolve = T._resolve_orig
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
  local config = require("codecompanion.config")
  local original_tavily = config.adapters.non_llm.tavily

  config.adapters.non_llm.tavily = "invalid"

  local self = { tool = { opts = { adapter = "valid_adapter", opts = {} } } }
  local got = call_tool(self, { query = "q" })
  h.eq(got.status, "error")

  config.adapters.non_llm.tavily = original_tavily
end

T["error when resolve returns nil"] = function()
  non_llm_adapters.resolve = function()
    return nil
  end
  local self = { tool = { opts = { adapter = "valid_adapter", opts = {} } } }
  local got = call_tool(self, { query = "q" })
  h.eq(got.status, "error")

  non_llm_adapters.resolve = T._resolve_orig
end

return T
