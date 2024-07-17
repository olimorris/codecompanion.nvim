local variables = require("codecompanion.strategies.chat.variables").new()
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
  -- Match '#' followed by word characters
  return [[\#\w*]]
end

function source:complete(_, callback)
  local items = {}
  for label, data in pairs(variables.vars) do
    table.insert(items, {
      label = "#" .. label,
      kind = require("cmp").lsp.CompletionItemKind.Variable,
      detail = data.description,
    })
  end

  callback({
    items = items,
    isIncomplete = false,
  })
end

return source
