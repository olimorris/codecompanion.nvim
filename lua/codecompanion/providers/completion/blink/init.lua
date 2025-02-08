--- @module 'blink.cmp'

local completion = require("codecompanion.completion")

local slash_commands = completion.slash_commands()
local tools = completion.tools()
local vars = completion.variables()

--- @class blink.cmp.Source
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
  local trigger_char = ctx.trigger.character or ctx.line:sub(ctx.bounds.start_col - 1, ctx.bounds.start_col - 1)

  --- @type lsp.Range
  local edit_range = {
    start = {
      line = ctx.bounds.line_number - 1,
      character = ctx.bounds.start_col - 2,
    },
    ["end"] = {
      line = ctx.bounds.line_number - 1,
      character = ctx.bounds.start_col + ctx.bounds.length,
    },
  }

  -- Slash commands
  if trigger_char == "/" then
    callback({
      context = ctx,
      is_incomplete_forward = false,
      is_incomplete_backward = false,
      items = vim
        .iter(slash_commands)
        :map(function(item)
          return {
            kind = vim.lsp.protocol.CompletionItemKind.Function,
            label = item.label:sub(2),
            textEdit = {
              newText = item.label,
              range = edit_range,
            },
            documentation = {
              kind = "plaintext",
              value = item.detail,
            },
            data = {
              type = "slash_command",
              from_prompt_library = item.from_prompt_library,
              config = item.config,
            },
          }
        end)
        :totable(),
    })

  -- Variables
  elseif trigger_char == "#" then
    callback({
      context = ctx,
      is_incomplete_forward = false,
      is_incomplete_backward = false,
      items = vim
        .iter(vars)
        :map(function(item)
          return {
            kind = vim.lsp.protocol.CompletionItemKind.Variable,
            label = item.label:sub(2),
            textEdit = {
              newText = item.label,
              range = edit_range,
            },
            documentation = {
              kind = "plaintext",
              value = item.detail,
            },
            data = { type = "variable" },
          }
        end)
        :totable(),
    })

  -- Agents and tools
  elseif trigger_char == "@" then
    callback({
      context = ctx,
      is_incomplete_forward = false,
      is_incomplete_backward = false,
      items = vim
        .iter(tools)
        :map(function(item)
          return {
            kind = vim.lsp.protocol.CompletionItemKind.Struct,
            label = item.label:sub(2),
            textEdit = {
              newText = item.label,
              range = edit_range,
            },
            documentation = {
              kind = "plaintext",
              value = item.detail,
            },
            data = { type = "tool" },
          }
        end)
        :totable(),
    })

  -- Nothing to show
  else
    callback()
  end
end

function M:execute(ctx, item)
  if vim.tbl_contains({ "variable", "tool" }, item.data.type) then
    return
  end

  -- Remove the text added by completion engine
  vim.api.nvim_buf_set_text(
    ctx.bufnr,
    item.textEdit.range.start.line,
    item.textEdit.range.start.character,
    item.textEdit.range.start.line,
    item.textEdit.range.start.character + #item.textEdit.newText,
    {}
  )

  -- Slash commands expect the command info to be in the item directly
  -- rather than in the data field, so we copy
  local item = vim.deepcopy(item)
  for k, v in pairs(item.data) do
    item[k] = v
  end

  local chat = require("codecompanion").buf_get_chat(ctx.bufnr)
  completion.slash_commands_execute(item, chat)

  vim.bo[ctx.bufnr].buflisted = false
end

return M
