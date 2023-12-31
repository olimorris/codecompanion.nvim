local M = {}

M.setup = function()
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
        level = vim.log.levels.ERROR,
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

M.static_commands = {
  {
    name = "Chat",
    description = "Open a chat buffer to converse with the OpenAI Completions API",
    action = function()
      require("openai").chat()
    end,
  },
  {
    name = "Inline Assistant Prompt",
    description = "Prompt the OpenAI assistant to write some code",
    action = function(context)
      require("openai").assistant(context)
    end,
  },
}

return M
