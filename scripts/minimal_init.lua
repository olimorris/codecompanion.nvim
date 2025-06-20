-- Add project root to runtime path
vim.cmd([[let &rtp.=','.getcwd()]])

-- Add dependencies to runtime path
vim.cmd("set rtp+=./deps/mini.nvim")
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

local minitest = require("mini.test")
if _G.MiniTest == nil then
  minitest.setup()
end
