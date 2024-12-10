---@diagnostic disable: missing-fields

--NOTE: Set config path to enable the copilot adapter to work.
--It will search the follwoing paths for the for copilot token:
--  - "$CODECOMPANION_TOKEN_PATH/github-copilot/hosts.json"
--  - "$CODECOMPANION_TOKEN_PATH/github-copilot/apps.json"
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
      -- Comment this out if you don't want to setup blink.cmp
      {
        "saghen/blink.cmp",
        lazy = false,
        build = "cargo build --release",
        opts = {
          -- 'enter' for mappings similar to 'super-tab' but with 'enter' to accept
          keymap = {
            preset = "enter",
            ["<S-Tab>"] = { "select_prev", "fallback" },
            ["<Tab>"] = { "select_next", "fallback" },
          },
          sources = {
            completion = {
              enabled_providers = { "lsp", "path", "buffer", "codecompanion" },
            },
            providers = {
              codecompanion = {
                name = "CodeCompanion",
                module = "codecompanion.providers.completion.blink",
                enabled = true,
              },
            },
          },
        },
      },
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

require("lazy.minit").repro({ spec = plugins })

-- Setup Tree-sitter
local ts_status, treesitter = pcall(require, "nvim-treesitter.configs")
if ts_status then
  treesitter.setup({
    ensure_installed = { "lua", "markdown", "markdown_inline", "yaml" },
    highlight = { enable = true },
  })
end
