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
  local agent_kind = require("cmp").lsp.CompletionItemKind.Struct
  local tool_kind = require("cmp").lsp.CompletionItemKind.Snippet

  local function item(label, data, kind)
    return {
      label = "@" .. label,
      kind = kind or tool_kind,
      name = label,
      config = self.config,
      callback = data.callback,
      detail = data.description,
      context = {
        bufnr = params.context.bufnr,
      },
    }
  end

  -- Add agents
  vim
    .iter(self.config.strategies.agent)
    :filter(function(label)
      return label ~= "tools"
    end)
    :each(function(label, data)
      table.insert(items, item(label, data, agent_kind))
    end)

  -- Add tools
  vim
    .iter(self.config.strategies.agent.tools)
    :filter(function(label)
      return label ~= "opts"
    end)
    :each(function(label, data)
      table.insert(items, item(label, data))
    end)

  callback({
    items = items,
    isIncomplete = false,
  })
end

return source
