local config = require("codecompanion").config
local SlashCommands = require("codecompanion.strategies.chat.slash_commands")

local source = {}

---@param chat CodeCompanion.Chat
function source.new(chat)
  return setmetatable({
    chat = chat,
  }, { __index = source })
end

function source:is_available()
  return vim.bo.filetype == "codecompanion"
end

function source:get_trigger_characters()
  return { "/" }
end

function source:get_keyword_pattern()
  return [[\w\+]]
end

function source:complete(params, callback)
  local items = {}
  local kind = require("cmp").lsp.CompletionItemKind.Function

  for name, data in pairs(config.strategies.chat.slash_commands) do
    if name ~= "opts" then
      table.insert(items, {
        label = "/" .. name,
        kind = kind,
        detail = data.description,
        Chat = self.chat,
        config = data,
        context = {
          bufnr = params.context.bufnr,
          cursor = params.context.cursor,
        },
      })
    end
  end

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
  if callback then
    callback()
  end
  return SlashCommands:execute(item)
end

return source
