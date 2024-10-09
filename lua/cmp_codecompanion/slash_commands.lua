local SlashCommands = require("codecompanion.strategies.chat.slash_commands")
local config = require("codecompanion.config")
local strategy = require("codecompanion.strategies")

local source = {}

function source.new()
  return setmetatable({}, { __index = source })
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
  local kind = require("cmp").lsp.CompletionItemKind.Function

  local slash_commands = vim
    .iter(config.strategies.chat.slash_commands)
    :filter(function(name)
      return name ~= "opts"
    end)
    :map(function(name, data)
      return {
        label = "/" .. name,
        kind = kind,
        detail = data.description,
        config = data,
        context = {
          bufnr = params.context.bufnr,
          cursor = params.context.cursor,
        },
      }
    end)
    :totable()

  local prompts = vim
    .iter(config.prompt_library)
    :filter(function(_, v)
      return v.opts and v.opts.is_slash_cmd and v.strategy == "chat"
    end)
    :map(function(_, v)
      return {
        label = "/" .. v.opts.short_name,
        kind = kind,
        detail = v.description,
        config = v,
        from_prompt_library = true,
        context = {
          bufnr = params.context.bufnr,
          cursor = params.context.cursor,
        },
      }
    end)
    :totable()

  local all_items = vim.tbl_extend("force", slash_commands, prompts)

  callback({
    items = all_items,
    isIncomplete = false,
  })
end

---Execute selected item
---@param item table The selected item from the completion menu
---@param callback function
---@return nil
function source:execute(item, callback)
  vim.api.nvim_set_current_line("")
  item.Chat = require("codecompanion").buf_get_chat(item.context.bufnr)

  if item.from_prompt_library then
    local prompts = strategy.evaluate_prompts(item.config.prompts, item.context)
    vim.iter(prompts):each(function(prompt)
      if prompt.role == config.constants.SYSTEM_ROLE then
        item.Chat:add_message(prompt, { visible = false })
      elseif prompt.role == config.constants.USER_ROLE then
        item.Chat:append_to_buf(prompt)
      end
    end)
  else
    SlashCommands:execute(item)
  end

  callback(item)
  vim.bo[item.context.bufnr].buflisted = false
end

return source
