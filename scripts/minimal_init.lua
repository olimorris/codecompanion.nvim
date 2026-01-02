vim.cmd([[let &rtp.=','.getcwd()]])
vim.cmd("set rtp+=deps/mini.nvim")
vim.cmd("set rtp+=deps/plenary.nvim")
vim.cmd("set rtp+=deps/nvim-treesitter")

-- Ensure mini.test is available
require("mini.test").setup()

vim.treesitter.language.register("markdown", "codecompanion")
