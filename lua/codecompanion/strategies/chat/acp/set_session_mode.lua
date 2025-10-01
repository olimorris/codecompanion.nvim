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

---Build prompt and mappings for vim.fn.confirm
---@param modes table[]
---@param current_mode_id string|nil
---@return string, string[], table<number, string>, table<string, number>
local function build_choices(modes, current_mode_id)
  local prompt = string.format("%s: %s?", util.capitalize(CONSTANTS.PROMPT_KIND), CONSTANTS.PROMPT_TITLE)
  local choices, index_to_mode, mode_to_index = {}, {}, {}

  for index, mode in ipairs(modes or {}) do
    local choice_label = mode_label(mode, current_mode_id)
    table.insert(choices, string.format("&%d %s", index, choice_label))
    if mode and mode.id then
      index_to_mode[index] = mode.id
      mode_to_index[mode.id] = index
    end
  end

  return prompt, choices, index_to_mode, mode_to_index
end

---Display the available modes and return the selected mode id (if any)
---@param chat CodeCompanion.Chat|nil
---@param opts { available_modes: table[], current_mode_id?: string|nil }
---@return string|nil
function M.show(chat, opts)
  opts = opts or {}
  local _ = chat
  local modes = opts.available_modes or {}
  if vim.tbl_isempty(modes) then
    return nil
  end

  local prompt, choices, index_to_mode, mode_to_index = build_choices(modes, opts.current_mode_id)
  if #choices == 0 then
    return nil
  end

  local default_choice = 1
  if opts.current_mode_id and mode_to_index[opts.current_mode_id] then
    default_choice = mode_to_index[opts.current_mode_id]
  end

  local picked = vim.fn.confirm(prompt, table.concat(choices, "\n"), default_choice, "Question")
  if picked <= 0 then
    return nil
  end

  return index_to_mode[picked]
end

return M
