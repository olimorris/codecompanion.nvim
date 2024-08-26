local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:is_available()
  local chat = require("codecompanion.strategies.chat").last_chat()
  return vim.bo.filetype == "codecompanion" and chat ~= nil and chat.bufnr == vim.api.nvim_get_current_buf()
end

source.get_position_encoding_kind = function()
  return "utf-8"
end

function source:get_trigger_characters()
  return { "/", " " }
end

---@param params cmp.SourceCompletionApiParams
---@param callback fun(response: CodeCompanion.SlashCommandCompletionResponse|nil)
function source:complete(params, callback)
  local input = params.context.cursor_before_line
  local chat = require("codecompanion.strategies.chat").last_chat()

  if not chat or not chat.slash_command_manager then
    return callback()
  end

  if not input:match("^/") then
    return callback()
  end

  local command = input:match("/(%w+)")
  local cmd = chat.slash_command_manager:get(command)

  if command and cmd then
    if input:match("/" .. command .. "%s$") then
      if cmd and cmd.complete then
        return cmd:complete(params, callback)
      end
    end

    return callback()
  else
    local items = {}

    for name, c in pairs(chat.slash_command_manager.commands) do
      local item = {
        label = name,
        kind = require("cmp").lsp.CompletionItemKind.Function,
        documentation = c.description,
        -- Because when executing source:execute, the corresponding command needs to be obtained through slash_command_name
        -- For the 'now' and 'terminal' commands, since they are executed directly, slash_command_name needs to be set
        -- Ensure that the corresponding command:execute is called
        slash_command_name = (name == "now" or name == "terminal") and name or nil,
      }

      table.insert(items, item)
    end

    return callback({ items = items, isIncomplete = false })
  end
end

---Executed after the item was selected.
---@param completion_item CodeCompanion.SlashCommandCompletionItem
---@param callback fun(completion_item: CodeCompanion.SlashCommandCompletionItem|nil)
function source:execute(completion_item, callback)
  local chat = require("codecompanion.strategies.chat").last_chat()
  if not chat or not chat.slash_command_manager then
    return callback()
  end

  local cmd = chat.slash_command_manager:get(completion_item.slash_command_name)

  if cmd and completion_item then
    -- remove current line
    vim.api.nvim_set_current_line("")

    return cmd:execute(completion_item, callback)
  end

  return callback()
end

---Resolve completion item (optional). This is called right before the completion is about to be displayed.
---Useful for setting the text shown in the documentation window (`completion_item.documentation`).
---@param completion_item CodeCompanion.SlashCommandCompletionItem
---@param callback fun(completion_item: CodeCompanion.SlashCommandCompletionItem|nil)
function source:resolve(completion_item, callback)
  local chat = require("codecompanion.strategies.chat").last_chat()
  if not chat or not chat.slash_command_manager then
    return callback()
  end

  local cmd = chat.slash_command_manager:get(completion_item.slash_command_name)
  if cmd then
    return cmd:resolve(completion_item, callback)
  end

  return callback()
end

return source
