local completion = require("codecompanion.completion")

local slash_commands = completion.slash_commands()
local tools = completion.tools()
local vars = completion.variables()

local M = {}

function M.new()
  return setmetatable({}, { __index = M })
end

function M:get_trigger_characters()
  return { "/", "#", "@" }
end

function M:enabled()
  return vim.bo.filetype == "codecompanion"
end

function M:get_completions(ctx, callback)
  -- Slash commands
  if ctx.trigger.character == "/" then
    return callback({
      context = ctx,
      is_incomplete_forward = false,
      is_incomplete_backward = false,
      items = vim
        .iter(slash_commands)
        :map(function(item)
          return {
            label = item.label:sub(2),
            ctx = ctx,
            from_prompt_library = item.from_prompt_library,
            config = item.config,
            type = "slash_command",
            kind = vim.lsp.protocol.CompletionItemKind.Function,
            insertText = "",
            documentation = {
              kind = "plaintext",
              value = item.detail,
            },
          }
        end)
        :totable(),
    })
  end

  -- Variables
  if ctx.trigger.character == "#" then
    return callback({
      context = ctx,
      is_incomplete_forward = false,
      is_incomplete_backward = false,
      items = vim
        .iter(vars)
        :map(function(item)
          return {
            label = item.label:sub(2),
            type = "variable",
            kind = vim.lsp.protocol.CompletionItemKind.Variable,
            insertText = item.label:sub(2),
            documentation = {
              kind = "plaintext",
              value = item.detail,
            },
          }
        end)
        :totable(),
    })
  end

  -- Agents and tools
  if ctx.trigger.character == "@" then
    return callback({
      context = ctx,
      is_incomplete_forward = false,
      is_incomplete_backward = false,
      items = vim
        .iter(tools)
        :map(function(item)
          return {
            label = item.label:sub(2),
            type = "tool",
            kind = vim.lsp.protocol.CompletionItemKind.Struct,
            insertText = item.label:sub(2),
            documentation = {
              kind = "plaintext",
              value = item.detail,
            },
          }
        end)
        :totable(),
    })
  end
end

function M:execute(ctx, item)
  if vim.tbl_contains({ "variable", "tool" }, item.type) then
    return
  end

  vim.api.nvim_buf_set_text(
    item.ctx.bufnr,
    item.ctx.bounds.line_number - 1,
    item.ctx.bounds.start_col - 1,
    item.ctx.bounds.line_number - 1,
    item.ctx.bounds.end_col,
    { "" }
  )

  local chat = require("codecompanion").buf_get_chat(item.ctx.bufnr)
  completion.slash_commands_execute(item, chat)

  vim.bo[item.ctx.bufnr].buflisted = false
end

return M
