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

local ensure_installed = {
  "go",
  "lua",
  "markdown",
  "markdown_inline",
  "python",
  "yaml",
}

local installed = require("nvim-treesitter.config").installed_parsers()
local not_installed = vim.tbl_filter(function(parser)
  return not vim.tbl_contains(installed, parser)
end, ensure_installed)

if #not_installed > 0 then
  require("nvim-treesitter").install(not_installed):wait(300000)
end

vim.treesitter.language.register("markdown", "codecompanion")

local minitest = require("mini.test")
if _G.MiniTest == nil then
  minitest.setup()
end
