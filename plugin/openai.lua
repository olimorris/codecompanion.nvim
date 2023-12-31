if vim.fn.has("nvim-0.9.0") == 0 then
  vim.api.nvim_err_writeln("OpenAI.nvim requires at least nvim-0.9.0")
  return
end

if vim.g.loaded_openai then
  return
end

local openai = require("openai")

vim.api.nvim_create_user_command("AIChat", function()
  openai.chat()
end, { desc = "" })

vim.api.nvim_create_user_command("AIAssistant", function()
  openai.assistant()
end, { desc = "", range = true })

vim.api.nvim_create_user_command("AICommands", function()
  openai.commands()
end, { desc = "", range = true })

vim.g.loaded_openai = true
