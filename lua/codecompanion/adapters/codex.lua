local log = require("codecompanion.utils.log")

---@class Codex.CLIAdapter: CodeCompanion.CLIAdapter
return {
  name = "codex",
  formatted_name = "Codex",
  type = "cli",
  protocol = "acp", -- Let RPC client know this uses ACP

  roles = {
    llm = "assistant",
    user = "user",
  },

  opts = {
    stream = true,
    tools = true,
    vision = false,
  },

  features = {
    text = true,
    sessions = true,
  },

  config = {
    manifest_path = "Cargo.toml",
    timeout = 30000,
  },

  env = {
    api_key = "OPENAI_API_KEY",
    manifest_path = function(self)
      return self.config.manifest_path
    end,
  },

  command = {
    "cargo",
    "run",
    "--bin",
    "codex",
    "--manifest-path",
    "${manifest_path}",
    "mcp",
  },

  -- ACP initialization parameters
  parameters = {
    protocolVersion = "2024-11-05",
    capabilities = {},
    clientInfo = {
      name = "codecompanion",
      version = "1.0.0",
    },
  },

  handlers = {
    ---Setup environment before starting
    setup = function(self)
      return true
    end,

    ---Handle Codex-specific notifications if needed
    session_update = function(self, params)
      -- Only if Codex has specific behavior different from standard ACP
      if params.sessionUpdate == "agentThoughtChunk" then
        log:trace("Codex reasoning: %s", params.content.text)
      end
    end,
  },
}
