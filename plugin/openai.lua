local openai = require("openai")

vim.api.nvim_create_user_command("AIChat", function()
  openai.chat()
end, { desc = "" })

vim.api.nvim_create_user_command("AIEdit", function(args)
  openai.edit(args.line1, args.line2)
end, {
  desc = "",
  range = true,
})
