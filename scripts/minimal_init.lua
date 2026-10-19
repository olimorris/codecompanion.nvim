vim.cmd([[let &rtp.=','.getcwd()]])
vim.cmd("set rtp+=deps/mini.nvim")
vim.cmd("set rtp+=deps/plenary.nvim")
vim.cmd("set rtp+=deps/nvim-treesitter")

-- Ensure mini.test is available
require("mini.test").setup()

-- Ensure consistent rendering
vim.o.termguicolors = true
vim.o.background = "dark"
vim.cmd("colorscheme default")

-- Install and setup Tree-sitter
require("nvim-treesitter").setup({
  install_dir = "deps/parsers",
})

local ok, err_or_ok = require("nvim-treesitter")
  .install({
    "lua",
    "make",
    "markdown",
    "markdown_inline",
    "yaml",
  }, { summary = true, max_jobs = 10 })
  :wait(1800000)

if not ok then
  print("ERROR: ", err_or_ok)
end

vim.treesitter.language.register("markdown", "codecompanion")

-- No test may reach the network. Anything that needs a response must stub the
-- layer it calls, be that the HTTP client's static methods or the adapter itself
local curl = require("codecompanion.utils.curl")
for _, method in ipairs({ "get", "post", "request", "get_sync", "post_sync", "request_sync" }) do
  curl[method] = function(opts)
    error(string.format("Test attempted a real HTTP request: %s %s", method:upper(), tostring(opts.url)))
  end
end
