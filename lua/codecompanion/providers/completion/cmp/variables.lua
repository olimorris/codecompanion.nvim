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

function source:get_trigger_characters()
  return { "#" }
end

function source:get_keyword_pattern()
  return [[\%(@\|#\|/\)\k*]]
end

function source:complete(_, callback)
  local items = require("codecompanion.providers.completion").variables()
  local kind = require("cmp").lsp.CompletionItemKind.Variable

  vim.iter(items):map(function(item)
    item.kind = kind
    item.insertText = string.format("#{%s}", item.label:sub(2))
    return item
  end)

  callback({
    items = items,
    isIncomplete = false,
  })
end

return source
