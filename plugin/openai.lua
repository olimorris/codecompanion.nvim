local openai = require("openai")

vim.api.nvim_create_user_command("AIChat", function()
  openai.open()
end, { desc = "" })

vim.api.nvim_create_user_command("AIEdit", function(args)
  openai.edit_text(args.line1, args.line2)
end, {
  desc = "",
  range = true,
})
