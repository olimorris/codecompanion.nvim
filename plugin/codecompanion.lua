if vim.g.loaded_codecompanion then
  return
end
vim.g.loaded_codecompanion = true

if vim.fn.has("nvim-0.11") == 0 then
  return vim.notify("CodeCompanion.nvim requires Neovim 0.11+", vim.log.levels.ERROR)
end

local config = require("codecompanion.config")
local util = require("codecompanion.utils")
local api = vim.api

api.nvim_set_hl(0, "CodeCompanionChatInfo", { link = "DiagnosticInfo", default = true })
api.nvim_set_hl(0, "CodeCompanionChatError", { link = "DiagnosticError", default = true })
api.nvim_set_hl(0, "CodeCompanionChatWarn", { link = "DiagnosticWarn", default = true })
api.nvim_set_hl(0, "CodeCompanionChatSubtext", { link = "Comment", default = true })
api.nvim_set_hl(0, "CodeCompanionChatFold", { link = "@markup.quote.markdown", default = true })
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
local visual_hl = api.nvim_get_hl(0, { name = "Visual" })
pcall(api.nvim_set_hl, 0, "CodeCompanionInlineDiffHint", { bg = visual_hl.bg, default = true })

-- Setup syntax highlighting for the chat buffer
local syntax_group = api.nvim_create_augroup("codecompanion.syntax", { clear = true })
api.nvim_create_autocmd("FileType", {
  pattern = "codecompanion",
  group = syntax_group,
  callback = vim.schedule_wrap(function()
    vim.iter(config.strategies.chat.variables):each(function(name)
      vim.cmd.syntax('match CodeCompanionChatVariable "#{' .. name .. '}"')
      vim.cmd.syntax('match CodeCompanionChatVariable "#{' .. name .. ':[^}]*}"')
      vim.cmd.syntax('match CodeCompanionChatVariable "#{' .. name .. ':[^}]*}{[^}]*}"')
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

local buf_group = api.nvim_create_augroup("codecompanion.buffers", { clear = true })

_G.codecompanion_last_terminal = nil
api.nvim_create_autocmd("TermEnter", {
  group = buf_group,
  desc = "Capture the last terminal buffer",
  callback = function(args)
    local bufnr = args.buf
    if vim.bo[bufnr].buftype == "terminal" then
      _G.codecompanion_last_terminal = bufnr
    end
  end,
})

_G.codecompanion_current_context = nil
api.nvim_create_autocmd("BufEnter", {
  group = buf_group,
  desc = "Capture the last buffer the user was in",
  callback = function(args)
    local bufnr = args.buf
    if not api.nvim_buf_is_valid(bufnr) then
      return
    end

    local buffer_config = config.strategies.chat.variables.buffer.opts
    local excluded = (buffer_config and buffer_config.excluded) or {}
    local excluded_fts = excluded.fts or {}
    local excluded_buftypes = excluded.buftypes or {}

    if
      not vim.tbl_contains(excluded_fts, vim.bo[bufnr].filetype)
      and not vim.tbl_contains(excluded_buftypes, vim.bo[bufnr].buftype)
    then
      _G.codecompanion_current_context = bufnr
      util.fire("ContextChanged", { bufnr = bufnr })
    end
  end,
})

-- Register the Tree-sitter filetype
vim.treesitter.language.register("markdown", "codecompanion")
