local config = require("openai.config")

local M = {}

local function get_max_length(tbl, field)
  local max_length = 0
  for _, str in ipairs(tbl) do
    local len = string.len(str[field])
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

  local name_pad = get_max_length(items, "name")
  local mode_pad = get_max_length(items, "mode")

  vim.ui.select(items, {
    prompt = "OpenAI.nvim",
    kind = "openai.nvim",
    format_item = function(item)
      return pad_string(item.name, name_pad)
        .. " │ "
        .. pad_string(item.mode, mode_pad)
        .. " │ "
        .. item.description
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
