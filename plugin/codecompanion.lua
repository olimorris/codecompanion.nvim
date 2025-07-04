if vim.g.loaded_codecompanion then
  return
end
vim.g.loaded_codecompanion = true

if vim.fn.has("nvim-0.11") == 0 then
  return vim.notify("CodeCompanion.nvim requires Neovim 0.11+", vim.log.levels.ERROR)
end

local config = require("codecompanion.config")
local api = vim.api

-- Set the highlight groups
api.nvim_set_hl(0, "CodeCompanionChatInfo", { link = "DiagnosticInfo", default = true })
api.nvim_set_hl(0, "CodeCompanionChatError", { link = "DiagnosticError", default = true })
api.nvim_set_hl(0, "CodeCompanionChatWarn", { link = "DiagnosticWarn", default = true })
api.nvim_set_hl(0, "CodeCompanionChatSubtext", { link = "Comment", default = true })
api.nvim_set_hl(0, "CodeCompanionChatHeader", { link = "@markup.heading.2.markdown", default = true })
api.nvim_set_hl(0, "CodeCompanionChatSeparator", { link = "@punctuation.special.markdown", default = true })
api.nvim_set_hl(0, "CodeCompanionChatTokens", { link = "Comment", default = true })
api.nvim_set_hl(0, "CodeCompanionChatTool", { link = "Special", default = true })
api.nvim_set_hl(0, "CodeCompanionChatToolGroup", { link = "Constant", default = true })
api.nvim_set_hl(0, "CodeCompanionChatToolSuccess", { link = "DiagnosticOK", default = true })
api.nvim_set_hl(0, "CodeCompanionChatToolSuccessIcon", { link = "DiagnosticOK", default = true })
api.nvim_set_hl(0, "CodeCompanionChatToolFailure", { link = "DiagnosticError", default = true })
api.nvim_set_hl(0, "CodeCompanionChatToolFailureIcon", { link = "Error", default = true })
api.nvim_set_hl(0, "CodeCompanionChatVariable", { link = "Identifier", default = true })
api.nvim_set_hl(0, "CodeCompanionVirtualText", { link = "Comment", default = true })

-- Setup syntax highlighting for the chat buffer
local group = "codecompanion.syntax"
api.nvim_create_augroup(group, { clear = true })
api.nvim_create_autocmd("FileType", {
  pattern = "codecompanion",
  group = group,
  callback = vim.schedule_wrap(function()
    vim.iter(config.strategies.chat.variables):each(function(name, var)
      vim.cmd.syntax('match CodeCompanionChatVariable "#{' .. name .. '}"')
      vim.cmd.syntax('match CodeCompanionChatVariable "#{' .. name .. '}{[^}]*}"')
    end)
    vim
      .iter(config.strategies.chat.tools)
      :filter(function(name)
        return name ~= "groups" and name ~= "opts"
      end)
      :each(function(name, _)
        vim.cmd.syntax('match CodeCompanionChatTool "@{' .. name .. '}"')
      end)
    vim.iter(config.strategies.chat.tools.groups):each(function(name, _)
      vim.cmd.syntax('match CodeCompanionChatToolGroup "@{' .. name .. '}"')
    end)
  end),
})

-- Set the diagnostic namespace for the chat buffer settings
config.INFO_NS = api.nvim_create_namespace("CodeCompanion-info")
config.ERROR_NS = api.nvim_create_namespace("CodeCompanion-error")

local diagnostic_config = {
  underline = false,
  virtual_text = {
    spacing = 2,
    severity = { min = vim.diagnostic.severity.INFO },
  },
  signs = false,
}
vim.diagnostic.config(diagnostic_config, config.INFO_NS)
vim.diagnostic.config(diagnostic_config, config.ERROR_NS)

-- Capture the last terminal buffer
_G.codecompanion_last_terminal = nil
api.nvim_create_autocmd("TermEnter", {
  desc = "Capture the last terminal buffer",
  callback = function()
    local bufnr = api.nvim_get_current_buf()
    if vim.bo[bufnr].buftype == "terminal" then
      _G.codecompanion_last_terminal = bufnr
    end
  end,
})

-- Register the Tree-sitter filetype
vim.treesitter.language.register("markdown", "codecompanion")
