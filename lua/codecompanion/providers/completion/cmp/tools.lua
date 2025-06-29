local source = {}

function source.new(config)
  return setmetatable({ config = config }, { __index = source })
end

function source:is_available()
  return vim.bo.filetype == "codecompanion"
end

source.get_position_encoding_kind = function()
  return "utf-8"
end

function source:get_trigger_characters()
  return { "@" }
end

function source:get_keyword_pattern()
  return [[\%(@\|#\|/\)\k*]]
end

function source:complete(params, callback)
  local items = require("codecompanion.providers.completion").tools()
  local agent_kind = require("cmp").lsp.CompletionItemKind.Struct
  local tool_kind = require("cmp").lsp.CompletionItemKind.Snippet

  vim.iter(items):map(function(item)
    if item.name == "tools" then
      item.kind = tool_kind
    else
      item.kind = agent_kind
    end
    item.config = self.config
    item.context = {
      bufnr = params.context.bufnr,
    }
    item.insertText = string.format("@{%s}", item.label:sub(2))
    return item
  end)

  callback({
    items = items,
    isIncomplete = false,
  })
end

return source
