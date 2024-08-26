local BaseSlashCommand = require("codecompanion.slash_commands").BaseSlashCommand
local api = vim.api
local fn = vim.fn

--- DiagnosticsCommand class for inserting diagnostic information with context.
--- @class CodeCompanion.DiagnosticsCommand : CodeCompanion.BaseSlashCommand
local DiagnosticsCommand = BaseSlashCommand:extend()

function DiagnosticsCommand:init(opts)
  opts = opts or {}
  BaseSlashCommand.init(self, opts)

  self.name = "diagnostics"
  self.description = "Insert diagnostic information with context"
end

--- Get context lines around a specific line
--- @param bufnr number The buffer number
--- @param lnum number The line number
--- @param context number The number of context lines
--- @return table
local function get_context_lines(bufnr, lnum, context)
  local start_line = math.max(0, lnum - context)
  local end_line = lnum + context
  local lines = api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)
  local result = {}
  for i, line in ipairs(lines) do
    table.insert(result, string.format("%d: %s", start_line + i, line))
  end
  return result
end

--- Complete file paths for the command.
--- @param params cmp.SourceCompletionApiParams
--- @param callback fun(response: CodeCompanion.SlashCommandCompletionResponse|nil)
---@diagnostic disable-next-line: unused-local
function DiagnosticsCommand:complete(params, callback)
  local chat = self.get_chat()
  if not chat then
    return callback()
  end

  local bufnr = chat.focus_bufnr
  local filepath = vim.fn.fnamemodify(api.nvim_buf_get_name(bufnr), ":.")
  local diagnostics = vim.diagnostic.get(bufnr)
  local formatted_diagnostics = {}

  ---@type CodeCompanion.SlashCommandCompletionResponse
  local items = {}

  for _, d in ipairs(diagnostics) do
    local context_lines = get_context_lines(bufnr, d.lnum, 5)
    local diagnostic_info = string.format("%s:%d:%d - %s", d.source, d.lnum, d.col, d.message)
    local context_info = table.concat(context_lines, "\n")
    table.insert(formatted_diagnostics, string.format("%s\nContext:\n%s", diagnostic_info, context_info))

    ---@type CodeCompanion.SlashCommandCompletionItem
    local item = {
      label = diagnostic_info,
      kind = require("cmp").lsp.CompletionItemKind.Text,
      slash_command_name = self.name,
      documentation = {
        kind = require("cmp").lsp.MarkupKind.Markdown,
        value = string.format("```diagnostics %s\n%s\nContext:\n%s\n```", filepath, diagnostic_info, context_info),
      },
    }

    table.insert(items, item)
  end

  -- insert a all diagnostics option at the top
  if #diagnostics > 0 then
    table.insert(items, 1, {
      label = "All diagnostics",
      kind = require("cmp").lsp.CompletionItemKind.Text,
      slash_command_name = self.name,
      documentation = {
        kind = require("cmp").lsp.MarkupKind.Markdown,
        value = string.format("```diagnostics %s\n%s\n```", filepath, table.concat(formatted_diagnostics, "\n\n")),
      },
    })

    -- vim.notify(vim.inspect(items))

    return callback({ items = items, isIncomplete = false })
  end

  return callback()
end

function DiagnosticsCommand:get_fold_text()
  return fn.expand("%:.")
end

return DiagnosticsCommand
