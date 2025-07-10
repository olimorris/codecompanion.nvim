---@diagnostic disable: missing-fields

--[[
NOTE: Set the config path to enable the copilot adapter to work.
It will search the following paths for a token:
  - "$CODECOMPANION_TOKEN_PATH/github-copilot/hosts.json"
  - "$CODECOMPANION_TOKEN_PATH/github-copilot/apps.json"
--]]
vim.env["CODECOMPANION_TOKEN_PATH"] = vim.fn.expand("~/.config")

vim.env.LAZY_STDPATH = ".repro"
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

-- Your CodeCompanion setup
local plugins = {
  {
    "olimorris/codecompanion.nvim",
    dependencies = {
      { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },
      { "nvim-lua/plenary.nvim" },
      -- Test with blink.cmp (delete if not required)
      {
        "saghen/blink.cmp",
        lazy = false,
        version = "*",
        opts = {
          keymap = {
            preset = "enter",
            ["<S-Tab>"] = { "select_prev", "fallback" },
            ["<Tab>"] = { "select_next", "fallback" },
          },
          cmdline = { sources = { "cmdline" } },
          sources = {
            default = { "lsp", "path", "buffer", "codecompanion" },
          },
        },
      },
      -- Test with nvim-cmp
      -- { "hrsh7th/nvim-cmp" },
    },
    opts = {
      --Refer to: https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua
      strategies = {
        --NOTE: Change the adapter as required
        chat = { adapter = "copilot" },
        inline = { adapter = "copilot" },
      },
      opts = {
        log_level = "DEBUG",
      },
    },
  },
}

-- Leaving this comment in to see if the issue author notices ;-)
-- This is so I can tell if they've really tested with their own minimal.lua file

require("lazy.minit").repro({ spec = plugins })

-- Setup Tree-sitter
local ts_status, treesitter = pcall(require, "nvim-treesitter.configs")
if ts_status then
  treesitter.setup({
    ensure_installed = { "lua", "markdown", "markdown_inline", "yaml", "diff" },
    highlight = { enable = true },
  })
end

-- Setup nvim-cmp
-- local cmp_status, cmp = pcall(require, "cmp")
-- if cmp_status then
--   cmp.setup({
--     mapping = cmp.mapping.preset.insert({
--       ["<C-b>"] = cmp.mapping.scroll_docs(-4),
--       ["<C-f>"] = cmp.mapping.scroll_docs(4),
--       ["<C-Space>"] = cmp.mapping.complete(),
--       ["<C-e>"] = cmp.mapping.abort(),
--       ["<CR>"] = cmp.mapping.confirm({ select = true }),
--       -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
--     }),
--   })
-- end
