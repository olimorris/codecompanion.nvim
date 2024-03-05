local config = require("codecompanion.config")

local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local info = vim.health.info or vim.health.report_info
local warn = vim.health.warn or vim.health.report_warn
local error = vim.health.error or vim.health.report_error

local fmt = string.format

local M = {}

M.plugins = {
  {
    name = "nvim-treesitter",
    plugin_name = "nvim-treesitter",
  },
  {
    name = "plenary.nvim",
    plugin_name = "plenary",
  },
  {
    name = "dressing.nvim",
    plugin_name = "dressing",
    optional = true,
  },
  {
    name = "edgy.nvim",
    plugin_name = "edgy",
    optional = true,
  },
}

M.libraries = {
  "curl",
}

M.env_vars = {
  {
    name = config.options.api_key,
  },
  {
    name = config.options.org_api_key,
    optional = true,
  },
}

local function plugin_available(name)
  local check, _ = pcall(require, name)
  return check
end

local function lib_available(lib)
  if vim.fn.executable(lib) == 1 then
    return true
  end
  return false
end

local function env_available(env)
  if os.getenv(env) ~= nil then
    return true
  end
  return false
end

function M.check()
  if vim.fn.has("nvim-0.9") == 0 then
    error("codecompanion.nvim requires Neovim 0.9.0+")
  end

  start("codecompanion.nvim report")

  local log = require("codecompanion.utils.log")
  info(fmt("Log file: %s", log.get_logfile()))

  for _, plugin in ipairs(M.plugins) do
    if plugin_available(plugin.plugin_name) then
      ok(fmt("%s installed", plugin.name))
    else
      if plugin.optional then
        warn(fmt("%s not found", plugin.name))
      else
        error(fmt("%s not found", plugin.name))
      end
    end
  end

  for _, library in ipairs(M.libraries) do
    if lib_available(library) then
      ok(fmt("%s installed", library))
    else
      error(fmt("%s not installed", library))
    end
  end

  -- for _, env in ipairs(M.env_vars) do
  --   if env_available(env.name) then
  --     ok(fmt("%s key found", env.name))
  --   else
  --     if env.optional then
  --       warn(fmt("%s key not found", env.name))
  --     else
  --       error(fmt("%s key not found", env.name))
  --     end
  --   end
  -- end
end

return M
