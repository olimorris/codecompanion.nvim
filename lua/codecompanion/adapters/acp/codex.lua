local log = require("codecompanion.utils.log")

---@class CodeCompanion.ACPAdapter.Codex: CodeCompanion.ACPAdapter
return {
  name = "codex",
  formatted_name = "Codex",
  type = "acp",
  roles = {
    llm = "assistant",
    user = "user",
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
  defaults = {
    manifest_path = "Users/Oli/Code/Neovim/Codex/codex-rs/Cargo.toml",
    timeout = 30000,
  },
  env = {
    api_key = "OPENAI_API_KEY",
    manifest_path = function(self)
      return self.defaults.manifest_path
    end,
  },
  parameters = {
    protocolVersion = "2024-11-05",
    capabilities = {},
    clientInfo = {
      name = "codecompanion",
      version = "1.0.0",
    },
  },
  handlers = {
    ---@param self CodeCompanion.ACPAdapter
    ---@return boolean
    setup = function(self)
      return true
    end,

    ---Function to run when the request has completed. Useful to catch errors
    ---@param self CodeCompanion.ACPAdapter
    ---@param data? table
    ---@return nil
    on_exit = function(self, data)
      return
    end,
  },
  protocol = {
    ---Authenticate with the ACP service.
    ---@param self CodeCompanion.ACPAdapter
    ---@return nil
    authenticate = function(self)
      return
    end,

    ---Start a new ACP session with the adapter
    ---@param self CodeCompanion.ACPAdapter
    ---@return nil
    new_session = function(self)
      return
    end,

    ---Load a previously saved ACP session
    ---@param self CodeCompanion.ACPAdapter
    ---@return nil
    load_session = function(self)
      return
    end,

    ---Prompt the ACP adapter with messages
    ---@param self CodeCompanion.ACPAdapter
    ---@param messages table
    ---@return table
    prompt = function(self, messages)
      return messages
    end,
  },
}
