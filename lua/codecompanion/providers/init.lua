---@class ProviderSpec
---@field module string module name
---@field name string provider name
---@field condition? function condition function to check if the provider is available

---@class Providers<T>: { [string]: T}

---@return boolean
local function is_coc_installed()
  if vim.g.did_coc_loaded == 1 or vim.g.coc_global_extensions ~= nil or vim.fn.exists("*coc#rpc#ready") == 1 then
    return true
  end

  for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
    if path:find("coc%.nvim") then
      return true
    end
  end

  return false
end

---@type Providers<ProviderSpec>
local configs = {
  -- Pickers / Action Palette
  telescope = { module = "telescope", name = "telescope" },
  mini_pick = { module = "mini.pick", name = "mini_pick" },
  fzf_lua = { module = "fzf-lua", name = "fzf_lua" },
  snacks = { module = "snacks", name = "snacks" },

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

      return is_coc_installed() and not has_blink and not has_cmp
    end,
  },
}

---@param opts { providers: table<string>, providers_config: Providers<ProviderSpec>, fallback: string }
---@return string available provider name
local function find_provider(opts)
  for _, key in ipairs(opts.providers) do
    local config = opts.providers_config[key]
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
      elseif config.condition then
        -- Module doesn't exist as a Lua module, but has a condition check
        -- (e.g., coc.nvim is a VimScript/Node.js plugin, not a Lua module)
        if config.condition() then
          return config.name
        end
      end
    end
  end
  return opts.fallback
end

---Wrap a detector so the plugins are only probed on first use
---@param detect fun(): string
---@return fun(): string
local function memoise(detect)
  local detected
  return function()
    if not detected then
      detected = detect()
    end
    return detected
  end
end

local action_palette_providers = memoise(function()
  local providers = { "telescope", "fzf_lua", "mini_pick", "snacks" }
  return find_provider({ providers = providers, providers_config = configs, fallback = "default" })
end)

local completion_providers = memoise(function()
  local providers = { "blink", "cmp", "coc", "default" }
  return find_provider({ providers = providers, providers_config = configs, fallback = "default" })
end)

local help_providers = memoise(function()
  local providers = { "telescope", "fzf_lua", "mini_pick", "snacks" }
  -- TODO: warn if falling back to telescope when it's also the first choice but others failed
  return find_provider({ providers = providers, providers_config = configs, fallback = "telescope" })
end)

local pick_providers = memoise(function()
  local providers = { "telescope", "fzf_lua", "mini_pick", "snacks" }
  return find_provider({ providers = providers, providers_config = configs, fallback = "default" })
end)

return {
  action_palette = action_palette_providers,
  completion = completion_providers,
  help = help_providers,
  pickers = pick_providers,
  is_coc_installed = is_coc_installed,

  ---Turn a configured provider (a name, or a detector function) into a name
  ---@param provider string|fun(): string
  ---@return string
  resolve_name = function(provider)
    if type(provider) == "function" then
      return provider()
    end
    return provider
  end,
}
