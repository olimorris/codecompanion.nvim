local cc_config = require("codecompanion.config")
local completion = require("codecompanion.providers.completion")

local trigger = require("codecompanion.triggers").mappings.acp_slash_commands

local source = {}

function source.new(config)
  return setmetatable({ config = config }, { __index = source })
end

function source:is_available()
  return vim.bo.filetype == "codecompanion" and cc_config.interactions.chat.slash_commands.opts.acp.enabled
end

function source:get_trigger_characters()
  return { trigger }
end

function source:get_keyword_pattern()
  local escaped = vim.pesc(trigger)
  return escaped .. [[\w\+]]
end

function source:complete(params, callback)
  local items = completion.acp_commands(params.context.bufnr)
  local kind = require("cmp").lsp.CompletionItemKind.Function

  vim.iter(items):map(function(item)
    item.kind = kind
    item.context = {
      bufnr = params.context.bufnr,
      cursor = params.context.cursor,
    }
  end)

  callback({
    items = items,
    isIncomplete = true, -- ACP commands can be updated dynamically via available_commands_update
  })
end

---Execute selected item by inserting command text
---@param item table The selected item from the completion menu
---@param callback function
---@return nil
function source:execute(item, callback)
  local text = completion.acp_commands_execute(item)

  -- Insert the command text at the current cursor position
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()

  -- Remove the trigger character and partial command
  local before = line:sub(1, col):gsub(string.format("%s%w*$", trigger), "")
  local after = line:sub(col + 1)
  local new_line = before .. text .. after

  vim.api.nvim_set_current_line(new_line)

  -- Position cursor after inserted text
  vim.api.nvim_win_set_cursor(0, { row, #before + #text })

  callback(item)
end

return source
