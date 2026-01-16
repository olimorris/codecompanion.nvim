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
  local tool_kind = require("cmp").lsp.CompletionItemKind.Snippet

  vim.iter(items):map(function(item)
    if item.name == "tools" then
      item.kind = tool_kind
    end
    item.config = self.config
    item.context = {
      bufnr = params.context.bufnr,
      cursor = params.context.cursor,
    }
    return item
  end)

  callback({
    items = items,
    isIncomplete = false,
  })
end

function source:execute(item, callback)
  local text = string.format("@{%s}", item.label:sub(2))
  vim.api.nvim_set_current_line(text)
  vim.api.nvim_win_set_cursor(0, { vim.fn.line("."), #text })
  callback(item)
end

return source
