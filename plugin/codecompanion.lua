if vim.fn.has("nvim-0.9.0") == 0 then
  return vim.api.nvim_err_writeln("CodeCompanion.nvim requires Neovim 0.9.0+")
end

if vim.g.loaded_codecompanion then
  return
end

local cmds = require("codecompanion.commands")
for _, cmd in ipairs(cmds) do
  vim.api.nvim_create_user_command(cmd.cmd, cmd.callback, cmd.opts)
end

vim.g.loaded_codecompanion = true
