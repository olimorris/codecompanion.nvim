local config = require("codecompanion.config")

local M = {}

M.mappings = {
  acp_slash_commands = config.opts.triggers.acp_slash_commands,
  editor_context = config.opts.triggers.editor_context,
  slash_commands = config.opts.triggers.slash_commands,
  tools = config.opts.triggers.tools,
}

M.chars = vim.tbl_values(M.mappings)

return M
