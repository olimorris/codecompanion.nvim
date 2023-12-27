local M = {}

M.setup = function()
  M.INFO_NS = vim.api.nvim_create_namespace("OpenAI-info")
  M.ERROR_NS = vim.api.nvim_create_namespace("OpenAI-error")

  local log = require("openai.log")
  log.set_root(log.new({
    handlers = {
      {
        type = "echo",
        level = vim.log.levels.WARN,
      },
      {
        type = "file",
        filename = "openai.log",
        level = vim.log.levels.TRACE,
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
