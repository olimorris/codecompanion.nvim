local config = require("codecompanion.config")

local M = {}

M.mappings = {
  acp_slash_commands = config.opts.triggers.acp_slash_commands,
  slash_commands = config.opts.triggers.slash_commands,
  tools = config.opts.triggers.tools,
  variables = config.opts.triggers.variables,
}

M.chars = {
  config.opts.triggers.acp_slash_commands,
  config.opts.triggers.slash_commands,
  config.opts.triggers.tools,
  config.opts.triggers.variables,
}

return M
