set rtp+=.
set rtp+=./misc/plenary
set rtp+=./misc/treesitter

set noswapfile

runtime! plugin/plenary.vim
runtime! plugin/nvim-treesitter.lua

lua <<EOF
local required_parsers = { 'lua', 'markdown', 'markdown_inline', 'yaml' }
local installed_parsers = require'nvim-treesitter.info'.installed_parsers()
local to_install = vim.tbl_filter(function(parser)
  return not vim.tbl_contains(installed_parsers, parser)
end, required_parsers)
if #to_install > 0 then
  -- fixes 'pos_delta >= 0' error - https://github.com/nvim-lua/plenary.nvim/issues/52
  vim.cmd('set display=lastline')
  -- make "TSInstall*" available
  vim.cmd 'runtime! plugin/nvim-treesitter.vim'
  vim.cmd('TSInstallSync ' .. table.concat(to_install, ' '))
end
EOF
