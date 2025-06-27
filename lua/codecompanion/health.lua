local start = vim.health.start or vim.health.report_start --[[@as function]]
local ok = vim.health.ok or vim.health.report_ok --[[@as function]]
local info = vim.health.info or vim.health.report_info --[[@as function]]
local warn = vim.health.warn or vim.health.report_warn --[[@as function]]
local error = vim.health.error or vim.health.report_error --[[@as function]]

local fmt = string.format

local M = {}

M.deps = {
  {
    name = "plenary.nvim",
    plugin_name = "plenary",
  },
  {
    name = "nvim-treesitter",
    plugin_name = "nvim-treesitter",
  },
}

M.parsers = {
  {
    name = "markdown",
  },
  {
    name = "yaml",
  },
}

M.libraries = {
  {
    name = "curl",
  },
  {
    name = "base64",
    optional = true,
  },
  {
    name = "rg",
    optional = true,
  },
}

M.adapters = {
  "anthropic",
  "ollama",
  "openai",
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

local function parser_available(filetype)
  local result, parser = pcall(vim.treesitter.get_parser, 0, filetype)
  return result and parser ~= nil
end

function M.check()
  if vim.fn.has("nvim-0.11") == 0 then
    error("codecompanion.nvim requires Neovim 0.11+")
  end

  local log = require("codecompanion.utils.log")
  info(fmt("Neovim version: %s.%s.%s", vim.version().major, vim.version().minor, vim.version().patch))
  info(fmt("Log file: %s", log.get_logfile()))

  start("Dependencies:")

  for _, plugin in ipairs(M.deps) do
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

  start("Tree-sitter parsers:")

  for _, parser in ipairs(M.parsers) do
    if parser_available(parser.name) then
      ok(fmt("%s parser installed", parser.name))
    else
      if parser.optional then
        warn(fmt("%s parser not found", parser.name))
      else
        error(fmt("%s parser not found", parser.name))
      end
    end
  end

  start("Libraries:")

  for _, library in ipairs(M.libraries) do
    if lib_available(library.name) then
      ok(fmt("%s installed", library.name))
    else
      if library.optional then
        warn(fmt("%s not found", library.name))
      else
        error(fmt("%s not found", library.name))
      end
    end
  end

  -- for _, name in ipairs(M.adapters) do
  --   local adapter = require("codecompanion.adapters." .. name)
  --
  --   if adapter.env then
  --     for _, v in pairs(adapter.env) do
  --       if env_available(v) then
  --         ok(fmt("%s key found (%s)", name, v))
  --       else
  --         warn(fmt("%s key not found (%s)", name, v))
  --       end
  --     end
  --   end
  -- end
end

return M
