local config = require("openai.config")

local M = {}

local function get_max_length(tbl)
  local max_length = 0
  for _, str in ipairs(tbl) do
    local len = string.len(str.name)
    if len > max_length then
      max_length = len
    end
  end

  return max_length
end

local function pad_string(str, max_length)
  local padding_needed = max_length - string.len(str)
  if padding_needed > 0 then
    -- Append the necessary padding
    return str .. string.rep(" ", padding_needed)
  else
    return str
  end
end

local function picker(context, items)
  if not items then
    items = config.static_commands
  end

  local padding = get_max_length(items)

  vim.ui.select(items, {
    prompt = "OpenAI.nvim",
    kind = "openai.nvim",
    format_item = function(item)
      return pad_string(item.name, padding) .. " │ " .. item.description
    end,
  }, function(selected)
    if not selected then
      return
    end

    return selected.action(context)
  end)
end

function M.select(context, items)
  picker(context, items)
end

return M
