if vim.g.loaded_codecompanion then
  return
end
vim.g.loaded_codecompanion = true

if vim.fn.has("nvim-0.11") == 0 then
  return vim.notify("CodeCompanion.nvim requires Neovim 0.11+", vim.log.levels.ERROR)
end

local api = vim.api

api.nvim_set_hl(0, "CodeCompanionChatError", { link = "DiagnosticError", default = true })
api.nvim_set_hl(0, "CodeCompanionChatFold", { link = "@markup.quote.markdown", default = true })
api.nvim_set_hl(0, "CodeCompanionChatHeader", { link = "@markup.heading.2.markdown", default = true })
api.nvim_set_hl(0, "CodeCompanionChatInfo", { link = "DiagnosticInfo", default = true })
api.nvim_set_hl(0, "CodeCompanionChatInfoBanner", { link = "WildMenu", default = true })
api.nvim_set_hl(0, "CodeCompanionChatSeparator", { link = "@punctuation.special.markdown", default = true })
api.nvim_set_hl(0, "CodeCompanionChatSubtext", { link = "Comment", default = true })
api.nvim_set_hl(0, "CodeCompanionChatTokens", { link = "Comment", default = true })
api.nvim_set_hl(0, "CodeCompanionChatTool", { link = "Special", default = true })
api.nvim_set_hl(0, "CodeCompanionChatToolFailure", { link = "DiagnosticError", default = true })
api.nvim_set_hl(0, "CodeCompanionChatToolFailureIcon", { link = "Error", default = true })
api.nvim_set_hl(0, "CodeCompanionChatToolGroup", { link = "Constant", default = true })
api.nvim_set_hl(0, "CodeCompanionChatToolInProgress", { link = "DiagnosticInfo", default = true })
api.nvim_set_hl(0, "CodeCompanionChatToolInProgressIcon", { link = "DiagnosticInfo", default = true })
api.nvim_set_hl(0, "CodeCompanionChatToolPending", { link = "DiagnosticWarn", default = true })
api.nvim_set_hl(0, "CodeCompanionChatToolPendingIcon", { link = "DiagnosticWarn", default = true })
api.nvim_set_hl(0, "CodeCompanionChatToolSuccess", { link = "DiagnosticOK", default = true })
api.nvim_set_hl(0, "CodeCompanionChatToolSuccessIcon", { link = "DiagnosticOK", default = true })
api.nvim_set_hl(0, "CodeCompanionChatVariable", { link = "Identifier", default = true })
api.nvim_set_hl(0, "CodeCompanionChatWarn", { link = "DiagnosticWarn", default = true })
api.nvim_set_hl(0, "CodeCompanionDiffAdd", { link = "DiffAdd", default = true })
api.nvim_set_hl(0, "CodeCompanionDiffChange", { link = "DiffChange", default = true })
api.nvim_set_hl(0, "CodeCompanionDiffDelete", { link = "DiffDelete", default = true })
api.nvim_set_hl(0, "CodeCompanionDiffHint", { link = "DiagnosticHint", default = true })
api.nvim_set_hl(0, "CodeCompanionDiffHintInline", { link = "Comment", default = true })
api.nvim_set_hl(0, "CodeCompanionVirtualText", { link = "Comment", default = true })

local syntax_group = api.nvim_create_augroup("codecompanion.syntax", { clear = true })

-- Setup syntax highlighting for the chat buffer
---@param bufnr? number
local make_hl_syntax = vim.schedule_wrap(function(bufnr)
  local config = require("codecompanion.config")

  -- Ref: #2344 - schedule_wrap defers execution to the next event loop cycle.
  -- By that time, the buffer may have been deleted (e.g. user closed the
  -- chat before the callback), so guard against this race condition.
  if bufnr and not api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.bo[bufnr or 0].syntax = "ON"

  -- As tools can now be created from outside of the config, apply a general pattern
  vim.cmd.syntax('match CodeCompanionChatTool "@{[^}]*}"')

  vim.iter(config.interactions.chat.variables):each(function(name)
    vim.cmd.syntax('match CodeCompanionChatVariable "#{' .. name .. '}"')
    vim.cmd.syntax('match CodeCompanionChatVariable "#{' .. name .. ':[^}]*}"')
    vim.cmd.syntax('match CodeCompanionChatVariable "#{' .. name .. ':[^}]*}{[^}]*}"')
  end)
end)

api.nvim_create_autocmd("FileType", {
  pattern = "codecompanion",
  group = syntax_group,
  callback = function(args)
    make_hl_syntax(args.buf)
  end,
})

local buf_group = api.nvim_create_augroup("codecompanion.buffers", { clear = true })

_G.codecompanion_last_terminal = nil
api.nvim_create_autocmd("TermEnter", {
  group = buf_group,
  desc = "Capture the last terminal buffer",
  callback = function(args)
    local bufnr = args.buf
    if not api.nvim_buf_is_valid(bufnr) then
      return
    end

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

    local config = require("codecompanion.config")

    local buffer_config = config.interactions.chat.variables.buffer.opts
    local excluded = (buffer_config and buffer_config.excluded) or {}
    local excluded_fts = excluded.fts or {}
    local excluded_buftypes = excluded.buftypes or {}

    if
      not vim.tbl_contains(excluded_fts, vim.bo[bufnr].filetype)
      and not vim.tbl_contains(excluded_buftypes, vim.bo[bufnr].buftype)
    then
      _G.codecompanion_current_context = bufnr
      require("codecompanion.utils").fire("ContextChanged", { bufnr = bufnr })
    end
  end,
})

vim.treesitter.language.register("markdown", "codecompanion")

-- Setup visual test command for diff development
require("codecompanion.utils.diff_test").setup()
