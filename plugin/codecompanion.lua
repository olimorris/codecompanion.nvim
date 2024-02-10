if vim.fn.has("nvim-0.9.0") == 0 then
  return vim.api.nvim_err_writeln("CodeCompanion.nvim requires Neovim 0.9.0+")
end

if vim.g.loaded_codecompanion then
  return
end

local codecompanion = require("codecompanion")

vim.api.nvim_create_user_command("CodeCompanionChat", function(opts)
  codecompanion.chat(opts)
end, { desc = "Open a Code Companion chat buffer", range = true })

vim.api.nvim_create_user_command("CodeCompanionActions", function(opts)
  codecompanion.actions(opts)
end, { desc = "Open the Code Companion actions palette", range = true })

vim.api.nvim_create_user_command("CodeCompanionToggle", function()
  codecompanion.toggle()
end, { desc = "Toggle a Code Companion chat buffer" })

vim.g.loaded_codecompanion = true
