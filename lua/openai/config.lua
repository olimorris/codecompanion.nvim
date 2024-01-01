local M = {}

local defaults = {
  api_key = "OPENAI_API_KEY",
  org_api_key = "OPENAI_ORG_KEY",
  log_level = "TRACE",
  display = {
    type = "popup",
    width = 0.8,
    height = 0.8,
  },
  commands = {
    {
      name = "Chat",
      strategy = "chat",
      description = "Open a chat buffer to converse with the OpenAI Completions API",
      mode = "n",
    },
    {
      name = "Inline Assistant",
      strategy = "author",
      description = "Prompt the OpenAI assistant to write/refactor some code",
      mode = "n,v",
      opts = {
        model = "gpt-4-1106-preview",
        user_input = true,
      },
      prompts = {
        [1] = {
          role = "system",
          message = [[I want you to act as a senior %s developer. I will ask you specific questions and I want you to return raw code only (no codeblocks and no explanations)]],
          variables = {
            "filetype",
          },
        },
      },
    },
    --   name = "Inline Advice",
    --   description = "Get the OpenAI assistant to provide some context or advice",
    --   mode = "v",
    --   action = function(context)
    --     require("openai").assistant(context)
    --   end,
    -- },
    {
      name = "LSP Assistant",
      description = "Get help from the OpenAI Completions API to fix LSP diagnostics",
      mode = "v",
      action = function(context)
        require("openai").lsp_assistant(context)
      end,
    },
  },
}

M.setup = function(opts)
  M.config = vim.tbl_deep_extend("force", {}, defaults, opts or {})

  M.INFO_NS = vim.api.nvim_create_namespace("OpenAI-info")
  M.ERROR_NS = vim.api.nvim_create_namespace("OpenAI-error")

  local log = require("openai.utils.log")
  log.set_root(log.new({
    handlers = {
      {
        type = "echo",
        level = vim.log.levels.WARN,
      },
      {
        type = "file",
        filename = "openai.log",
        level = vim.log.levels[M.config.log_level],
      },
    },
  }))

  local diagnostic_config = {
    underline = false,
    virtual_text = {
      severity = { min = vim.diagnostic.severity.INFO },
    },
    signs = false,
  }
  vim.diagnostic.config(diagnostic_config, M.INFO_NS)
  vim.diagnostic.config(diagnostic_config, M.ERROR_NS)
end

return M
