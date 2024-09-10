local tools = require("codecompanion.strategies.chat.tools").new().tools
local variables = require("codecompanion.strategies.chat.variables").new().vars

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
  return { "@", "#" }
end

function source:get_keyword_pattern()
  return [[\%(@\|#\|/\)\k*]]
end

function source:complete(_, callback)
  local items = {}
  local kind = require("cmp").lsp.CompletionItemKind.Variable

  for label, data in pairs(variables) do
    table.insert(items, {
      label = "#" .. label,
      kind = kind,
      detail = data.description,
    })
  end

  for label, data in pairs(tools) do
    if label ~= "opts" then
      table.insert(items, {
        label = "@" .. label,
        kind = kind,
        detail = data.description,
      })
    end
  end

  callback({
    items = items,
    isIncomplete = false,
  })
end

return source
