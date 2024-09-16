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
  local items = {}
  local kind = require("cmp").lsp.CompletionItemKind.Snippet

  for label, data in pairs(self.config.strategies.agent.tools) do
    if label ~= "opts" then
      table.insert(items, {
        label = "@" .. label,
        kind = kind,
        name = label,
        config = self.config,
        callback = data.callback,
        detail = data.description,
        context = {
          bufnr = params.context.bufnr,
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
  local Chat = require("codecompanion").buf_get_chat(item.context.bufnr)
  Chat:add_tool(item)

  callback(item)
  vim.bo[item.context.bufnr].buflisted = false
end

return source
