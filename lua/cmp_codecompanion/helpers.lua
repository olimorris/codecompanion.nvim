local config = require("codecompanion").config

local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:is_available()
  return vim.bo.filetype == "codecompanion"
end

source.get_position_encoding_kind = function()
  return "utf-8"
end

function source:get_keyword_pattern()
  -- Match '@' followed by word characters
  return [[@\w*]]
end

function source:complete(_, callback)
  local items = {}
  for label, data in pairs(config.strategies.chat.helpers) do
    table.insert(items, {
      label = "@" .. label,
      kind = require("cmp").lsp.CompletionItemKind.Keyword,
      detail = data.description,
    })
  end

  callback({
    items = items,
    isIncomplete = false,
  })
end

return source
