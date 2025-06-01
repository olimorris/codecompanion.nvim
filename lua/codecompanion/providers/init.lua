---@class ProviderSpec
---@field module string module name
---@field name string provider name
---@field condition? function condition function to check if the provider is available

---@class Providers<T>: { [string]: T}

---@type Providers<ProviderSpec>
local configs = {
  -- Pickers / Action Palette
  telescope = { module = "telescope", name = "telescope" },
  mini_pick = { module = "mini.pick", name = "mini_pick" },
  fzf_lua = { module = "fzf-lua", name = "fzf_lua" },
  snacks = {
    module = "snacks",
    name = "snacks",
    condition = function(snacks)
      -- Snacks can be installed but the Picker is disabled
      return snacks and snacks.config.picker.enabled
    end,
  },

  -- Diffs
  mini_diff = {
    module = "mini.diff",
    name = "mini_diff",
    condition = function()
      -- MiniDiff only works correctly if initialized,
      -- which sets the global variable
      return _G.MiniDiff ~= nil
    end,
  },

  -- Completion
  blink = { module = "blink.cmp", name = "blink" },
  cmp = {
    module = "cmp",
    name = "cmp",
    condition = function()
      local has_cmp, _ = pcall(require, "cmp")
      local has_blink, _ = pcall(require, "blink.cmp")
      return has_cmp and not has_blink
    end,
  },
  coc = {
    module = "coc",
    name = "coc",
    condition = function()
      local has_cmp, _ = pcall(require, "cmp")
      local has_blink, _ = pcall(require, "blink.cmp")
      local has_coc = vim.fn.exists("*coc#rpc#ready") == 1
      return has_coc and not has_blink and not has_cmp
    end,
  },
}

---@param providers table<string> Provider names
---@param providers_config Providers<ProviderSpec> Provider configs
---@param fallback string Fallback provider name
---@return string available provider name
local function find_provider(providers, providers_config, fallback)
  for _, key in ipairs(providers) do
    local config = providers_config[key]
    if config then
      local success, loaded_module = pcall(require, config.module)
      if success then
        if config.condition then
          if config.condition(loaded_module) then
            return config.name
          end
        else
          return config.name
        end
      end
    end
  end
  return fallback
end

---Get the default Action Palette provider
---@return string
local function action_palette_providers()
  local providers = { "telescope", "fzf_lua", "mini_pick", "snacks" }
  return find_provider(providers, configs, "default")
end

---Get the default Diff provider
---@return string
local function diff_providers()
  local providers = { "mini_diff" }
  return find_provider(providers, configs, "default")
end

---Get the default Completion provider
---@return string
local function completion_providers()
  local providers = { "blink", "cmp", "coc", "default" }
  return find_provider(providers, configs, "default")
end

---Get the default Vim Help provider
---@return string
local function help_providers()
  local providers = { "telescope", "fzf_lua", "mini_pick", "snacks" }
  -- TODO: warn if falling back to telescope when it's also the first choice but others failed
  return find_provider(providers, configs, "telescope")
end

---Get the default picker provider
---@return string
local function pick_providers()
  local providers = { "telescope", "fzf_lua", "mini_pick", "snacks" }
  return find_provider(providers, configs, "default")
end

---Get the default image providers
---@return string
local function image_providers()
  local providers = { "telescope", "snacks" }
  return find_provider(providers, configs, "default")
end

return {
  action_palette = action_palette_providers(),
  completion = completion_providers(),
  diff = diff_providers(),
  help = help_providers(),
  images = image_providers(),
  pickers = pick_providers(),
}
