if vim.fn.has("nvim-0.9.0") == 0 then
  vim.api.nvim_err_writeln("CodeCompanion.nvim requires at least nvim-0.9.0")
  return
end

if vim.g.loaded_codecompanion then
  return
end

local codecompanion = require("codecompanion")

vim.api.nvim_create_user_command("CodeCompanionChat", function()
  codecompanion.chat()
end, { desc = "" })

vim.api.nvim_create_user_command("CodeCompanionCommands", function()
  codecompanion.commands()
end, { desc = "", range = true })

vim.g.loaded_codecompanion = true
