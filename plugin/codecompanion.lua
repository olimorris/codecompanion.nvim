if vim.fn.has("nvim-0.9.0") == 0 then
  return vim.api.nvim_err_writeln("CodeCompanion.nvim requires at least nvim-0.9.0")
end

if vim.g.loaded_codecompanion then
  return
end

local codecompanion = require("codecompanion")

vim.api.nvim_create_user_command("CodeCompanionChat", function()
  codecompanion.chat()
end, { desc = "" })

vim.api.nvim_create_user_command("CodeCompanionActions", function()
  codecompanion.actions()
end, { desc = "", range = true })

vim.api.nvim_create_user_command("CodeCompanionToggle", function()
  codecompanion.toggle()
end, { desc = "" })

vim.g.loaded_codecompanion = true
