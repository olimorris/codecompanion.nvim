---@class ProviderSpec
---@field module string module name
---@field name string provider name
---@field condition? function condition function to check if the provider is available

---@class Providers<T>: { [string]: T}

---@type Providers<ProviderSpec>
local all_provider_configs = {
  telescope = { module = "telescope", name = "telescope" },
  mini_pick = { module = "mini.pick", name = "mini_pick" },
  snacks = {
    module = "snacks",
    name = "snacks",
    condition = function(snacks_module)
      -- User might have Snacks installed but picker might be disabled
      return snacks_module and snacks_module.config.picker.enabled
    end,
  },
  mini_diff = { module = "mini.diff", name = "mini_diff" },
  fzf_lua = { module = "fzf-lua", name = "fzf_lua" },
}

---@param preferred_provider_keys table<string> table of provider names
---@param master_configs Providers<ProviderSpec> table of all provider configurations
---@param default_name string fallback provider name
---@return string available provider name
local function find_provider(preferred_provider_keys, master_configs, default_name)
  for _, key in ipairs(preferred_provider_keys) do
    local config = master_configs[key]
    if config then
      local success, loaded_module = pcall(require, config.module)
      if success then
        if config.condition then
          if config.condition(loaded_module) then
            return config.name
          end
        else
          return config.name -- No condition, module loaded successfully
        end
      end
    end
  end
  return default_name
end

---Get the default Action Palette provider
---@return string
local function action_palette_providers()
  local preferred_keys = { "telescope", "fzf_lua", "mini_pick", "snacks" }
  return find_provider(preferred_keys, all_provider_configs, "default")
end

---Get the default Diff provider
---@return string
local function diff_providers()
  local preferred_keys = { "mini_diff" }
  return find_provider(preferred_keys, all_provider_configs, "default")
end

---Get the default Vim Help provider
---@return string
local function help_providers()
  local preferred_keys = { "telescope", "fzf_lua", "mini_pick", "snacks" }
  -- TODO: warn if falling back to telescope when it's also the first choice but others failed
  return find_provider(preferred_keys, all_provider_configs, "telescope")
end

---Get the default picker provider
---@return string
local function pick_providers()
  local preferred_keys = { "telescope", "fzf_lua", "mini_pick", "snacks" }
  return find_provider(preferred_keys, all_provider_configs, "default")
end

return {
  action_palette = action_palette_providers(),
  diff = diff_providers(),
  help = help_providers(),
  pickers = pick_providers(),
}
