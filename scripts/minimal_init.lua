vim.cmd([[let &rtp.=','.getcwd()]])
vim.cmd("set rtp+=deps/mini.nvim")
vim.cmd("set rtp+=./deps/plenary.nvim")
vim.cmd("set rtp+=./deps/nvim-treesitter")

-- Ensure mini.test is available
require("mini.test").setup()

-- Install and setup Tree-sitter
require("nvim-treesitter").setup({
  install_dir = "deps/parsers",
})

require("nvim-treesitter")
  .install({
    "lua",
    "markdown",
    "markdown_inline",
    "yaml",
  })
  :wait(300000)

vim.treesitter.language.register("markdown", "codecompanion")
