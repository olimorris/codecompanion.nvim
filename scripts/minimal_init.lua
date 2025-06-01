vim.cmd([[let &rtp.=','.getcwd()]])

vim.cmd("set rtp+=./deps/plenary.nvim")
vim.cmd("set rtp+=./deps/nvim-treesitter")

-- Install and setup Tree-sitter
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

-- Set up 'mini.test' only when calling headless Neovim (like with `make test`)
if #vim.api.nvim_list_uis() == 0 then
  -- Add 'mini.nvim' to 'runtimepath' to be able to use 'mini.test'
  -- Assumed that 'mini.nvim' is stored in 'deps/mini.nvim'
  vim.cmd("set rtp+=deps/mini.nvim")

  -- Set up 'mini.test'
  require("mini.test").setup()
end
