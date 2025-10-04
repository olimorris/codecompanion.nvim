local util = require("codecompanion.utils")

local M = {}

local CONSTANTS = {
  PROMPT_TITLE = "Set Session Mode",
  PROMPT_KIND = "session mode",
}

---Build a human readable label for a mode entry
---@param mode table
---@param current_mode_id string|nil
---@return string
local function mode_label(mode, current_mode_id)
  local name = mode and (mode.name or mode.displayName or mode.id)
  if type(name) ~= "string" or name == "" then
    name = tostring(mode and mode.id or "Unknown")
  end

  if current_mode_id and mode and mode.id == current_mode_id then
    name = string.format("%s (current)", name)
  end

  return name
end

---Build prompt and choice entries for the session mode selector
---@param modes table[]
---@param current_mode_id string|nil
---@return string, table[], number
local function build_choices(modes, current_mode_id)
  local prompt = string.format("%s: %s?", util.capitalize(CONSTANTS.PROMPT_KIND), CONSTANTS.PROMPT_TITLE)
  local entries = {}
  local default_index = 1

  for _, mode in ipairs(modes or {}) do
    if type(mode) == "table" and mode.id then
      local position = #entries + 1
      table.insert(entries, {
        id = mode.id,
        mode = mode,
        label = mode_label(mode, current_mode_id),
      })
      if current_mode_id and mode.id == current_mode_id then
        default_index = position
      end
    end
  end

  return prompt, entries, default_index
end

---Display the available modes and invoke a callback with the selection
---@param chat CodeCompanion.Chat|nil
---@param opts { available_modes: table[], current_mode_id?: string|nil, on_select?: fun(mode_id: string|nil, mode: table|nil, index?: number) }
function M.show(chat, opts)
  opts = opts or {}
  local _ = chat
  local modes = opts.available_modes or {}
  if vim.tbl_isempty(modes) then
    if type(opts.on_select) == "function" then
      opts.on_select(nil, nil)
    end
    return
  end

  local prompt, entries, default_index = build_choices(modes, opts.current_mode_id)
  if #entries == 0 then
    if type(opts.on_select) == "function" then
      opts.on_select(nil, nil)
    end
    return
  end

  vim.ui.select(entries, {
    prompt = prompt,
    default = default_index,
    kind = "codecompanion_acp_session_mode",
    format_item = function(item)
      return item.label
    end,
  }, function(choice, idx)
    local selected_mode_id = choice and choice.id or nil
    local selected_mode = choice and choice.mode or nil
    if type(opts.on_select) == "function" then
      opts.on_select(selected_mode_id, selected_mode, idx)
    end
  end)
end

return M
