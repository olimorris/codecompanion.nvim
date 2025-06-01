vim.cmd([[let &rtp.=','.getcwd()]])

vim.cmd("set rtp+=./deps/plenary.nvim")
vim.cmd("set rtp+=./deps/nvim-treesitter")

-- Install and setup Tree-sitter
require("nvim-treesitter").setup({
  install_dir = "deps/parsers",
})
require("nvim-treesitter")
  .install({
    "go",
    "lua",
    "markdown",
    "markdown_inline",
    "python",
    "yaml",
  })
  :wait(300000)
vim.treesitter.language.register("markdown", "codecompanion")

vim.cmd("set rtp+=deps/mini.nvim")
require("mini.test").setup()
