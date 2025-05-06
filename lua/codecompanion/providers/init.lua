---Get the default Action Palette provider
---@return string
local function action_palette_providers()
  if pcall(require, "telescope") then
    return "telescope"
  elseif pcall(require, "mini.pick") then
    return "mini_pick"
  elseif pcall(require, "snacks") then
    return "snacks"
  else
    return "default"
  end
end

---Get the default Diff provider
---@return string
local function diff_providers()
  if pcall(require, "mini.diff") then
    return "mini_diff"
  else
    return "default"
  end
end

---Get the default Vim Help provider
---@return string
local function help_providers()
  if pcall(require, "telescope") then
    return "telescope"
  elseif pcall(require, "snacks") then
    return "snacks"
  elseif pcall(require, "mini.pick") then
    return "mini_pick"
  elseif pcall(require, "fzf-lua") then
    return "fzf_lua"
  else
    return "telescope" -- @todo: warn
  end
end

---Get the default picker provider
---@return string
local function pick_providers()
  if pcall(require, "telescope") then
    return "telescope"
  elseif pcall(require, "snacks") then
    return "snacks"
  elseif pcall(require, "mini.pick") then
    return "mini_pick"
  elseif pcall(require, "fzf-lua") then
    return "fzf_lua"
  else
    return "default"
  end
end

return {
  action_palette = action_palette_providers(),
  diff = diff_providers(),
  help = help_providers(),
  pickers = pick_providers(),
}
