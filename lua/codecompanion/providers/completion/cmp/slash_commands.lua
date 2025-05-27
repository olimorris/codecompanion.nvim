local SlashCommands = require("codecompanion.strategies.chat.slash_commands")
local completion = require("codecompanion.providers.completion")
local strategy = require("codecompanion.strategies")

local source = {}

function source.new(config)
  return setmetatable({ config = config }, { __index = source })
end

function source:is_available()
  return vim.bo.filetype == "codecompanion"
end

function source:get_trigger_characters()
  return { "/" }
end

function source:get_keyword_pattern()
  return [[/\w\+]]
end

function source:complete(params, callback)
  local items = completion.slash_commands()
  local kind = require("cmp").lsp.CompletionItemKind.Function

  vim.iter(items):map(function(item)
    item.kind = kind
    item.context = {
      bufnr = params.context.bufnr,
      cursor = params.context.cursor,
    }
  end)

  callback({
    items = items,
    isIncomplete = false,
  })
end

---Execute selected item
---@param item table The selected item from the completion menu
---@param callback function
---@return nil
function source:execute(item, callback)
  vim.api.nvim_set_current_line("")
  local chat = require("codecompanion").buf_get_chat(item.context.bufnr)

  completion.slash_commands_execute(item, chat)

  callback(item)
  vim.bo[item.context.bufnr].buflisted = false
end

return source
