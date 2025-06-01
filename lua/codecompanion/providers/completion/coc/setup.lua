local cocCompletion = require("codecompanion.providers.completion.coc")

_G.codecompanion_coc_init = cocCompletion.init
_G.codecompanion_coc_complete = cocCompletion.complete
_G.codecompanion_coc_execute = cocCompletion.execute

vim.api.nvim_create_autocmd("VimEnter", {
  callback = cocCompletion.ensure_autoload_file,
})
vim.api.nvim_create_autocmd("FileType", {
  pattern = "codecompanion",
  callback = cocCompletion.ensure_buffer_attached,
})
