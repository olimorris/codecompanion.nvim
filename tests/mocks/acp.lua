local M = {}

local DEFAULT_ADAPTER = {
  name = "test_acp",
  type = "acp",
  handlers = {
    form_messages = function(_, messages)
      return messages
    end,
  },
}

---Create a Connection instance with transport methods stubbed for tests.
---@param opts? { adapter?: table, config_options?: table, session_id?: string }
---@return CodeCompanion.ACP.Connection
function M.new(opts)
  opts = opts or {}

  local Connection = require("codecompanion.acp")
  local PromptBuilder = require("codecompanion.acp.prompt_builder")

  local adapter = opts.adapter or DEFAULT_ADAPTER
  local session_id = opts.session_id or "test-session-123"

  local conn = Connection.new({ adapter = adapter })
  conn.adapter_modified = adapter
  conn._config_options = opts.config_options or {}
  conn._agent_info = { agentCapabilities = {}, authMethods = {}, protocolVersion = 1 }

  conn.connect_and_authenticate = function(self)
    self._initialized = true
    self._authenticated = true
    self._state.handle = self._state.handle or {}
    return self
  end

  conn.ensure_session = function(self)
    self.session_id = session_id
    return true
  end

  conn.is_ready = function(self)
    return self._initialized == true and self._authenticated == true
  end

  conn.disconnect = function(self)
    self._state.handle = nil
    self.session_id = nil
  end

  conn.session_prompt = function(self, messages)
    local builder = PromptBuilder.new(self, messages)
    builder.send = function(s)
      _G.last_prompt_request = s
      return { shutdown = function() end }
    end
    return builder
  end

  return conn
end

return M
