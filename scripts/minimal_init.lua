vim.cmd([[let &rtp.=','.getcwd()]])

vim.cmd("set rtp+=./deps/plenary.nvim")
vim.cmd("set rtp+=./deps/nvim-treesitter")

-- Install and setup Tree-sitter
require("nvim-treesitter").setup()
local required_parsers = { "go", "lua", "markdown", "markdown_inline", "python", "yaml" }
local installed_parsers = require("nvim-treesitter.info").installed_parsers()
local to_install = vim.tbl_filter(function(parser)
  return not vim.tbl_contains(installed_parsers, parser)
end, required_parsers)

if #to_install > 0 then
  -- fixes 'pos_delta >= 0' error - https://github.com/nvim-lua/plenary.nvim/issues/52
  vim.cmd("set display=lastline")
  -- make "TSInstall*" available
  vim.cmd("runtime! plugin/nvim-treesitter.vim")
  vim.cmd("TSInstallSync " .. table.concat(to_install, " "))
end

-- Set up 'mini.test' only when calling headless Neovim (like with `make test`)
if #vim.api.nvim_list_uis() == 0 then
  -- Add 'mini.nvim' to 'runtimepath' to be able to use 'mini.test'
  -- Assumed that 'mini.nvim' is stored in 'deps/mini.nvim'
  vim.cmd("set rtp+=deps/mini.nvim")

  -- Set up 'mini.test'
  require("mini.test").setup()
end
