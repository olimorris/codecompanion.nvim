local health = vim.health or require("health")
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error

local fmt = string.format

local M = {}

M.plugins = {
  {
    name = "nvim-treesitter/nvim-treesitter",
  },
  {
    name = "nvim-lua/plenary.nvim",
  },
  {
    name = "stevearc/dressing.nvim",
    optional = true,
  },
  {
    name = "folke/edgy.nvim",
    optional = true,
  },
}

M.libraries = {
  "curl",
}

local function library_available(cmd)
  if vim.fn.executable(cmd) == 1 then
    return true
  end

  return false
end

local function plugin_available(name)
  local check, _ = pcall(require, name)
  return check
end

function M.check()
  if vim.fn.has("nvim-0.9") == 0 then
    health.error("CodeCompanion.nvim requires Neovim 0.9.0+")
  end

  health.start("Checking neovim plugin dependencies")

  for _, plugin in ipairs(M.plugins) do
    if plugin_available(plugin.name) then
      ok(plugin.name .. " installed.")
    else
      if plugin.optional then
        warn(fmt("Optional dependency '%s' not found.", plugin.name))
      else
        error(fmt("Dependency '%s' not found!", plugin.name))
      end
    end
  end

  health.start("Checking library dependencies")

  for _, library in ipairs(M.libraries) do
    if library_available(library) then
      ok(fmt("%s installed.", library))
    else
      error(fmt("%s not installed!", library))
    end
  end
end

return M
