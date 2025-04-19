local function get_default_pick_provider()
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

local default_pick_provider = get_default_pick_provider()

local function get_default_help_provider()
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

local default_help_provider = get_default_help_provider()

local function get_default_action_palette_provider()
  if pcall(require, "telescope") then
    return "telescope"
  elseif pcall(require, "mini.pick") then
    return "mini_pick"
  else
    return "default"
  end
end

local default_action_palette_provider = get_default_action_palette_provider()

local function get_default_diff_provider()
  if pcall(require, "mini_diff") then
    return "mini_diff"
  else
    return "default"
  end
end

local default_diff_provider = get_default_diff_provider()

return {
  pick_provider = default_pick_provider,
  help_provider = default_help_provider,
  action_palette_provider = default_action_palette_provider,
  diff_provider = default_diff_provider,
}
