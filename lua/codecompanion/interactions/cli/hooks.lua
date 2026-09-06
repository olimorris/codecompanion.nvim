local config = require("codecompanion.config")
local files = require("codecompanion.utils.files")
local utils = require("codecompanion.utils")

local api = vim.api

local M = {}

local CONSTANTS = {
  MARKER = "$CODECOMPANION_HOOK",
}

---@class CodeCompanion.CLI.Hooks.Integration
---@field name string
---@field hooks table<string, string> The agent's hook events, mapped to the script's actions
---@field settings string The agent's settings file, relative to the home directory
---@field script string Filename beneath `interactions/cli/integrations/`

---@type table<string, CodeCompanion.CLI.Hooks.Integration>
local INTEGRATIONS = {
  claude = {
    name = "Claude Code",
    hooks = {
      Notification = "approval_requested",
      PermissionRequest = "approval_requested",
      PostToolUse = "approval_finished",
      Stop = "done",
      UserPromptSubmit = "submitted",
    },
    settings = ".claude/settings.json",
    script = "claude.sh",
  },
}

---The script an agent's hooks call
---@param cmd string
---@return string|nil
function M.script_for(cmd)
  local integration = INTEGRATIONS[vim.fs.basename(cmd)]
  if not integration then
    return nil
  end

  local path = vim.fs.joinpath("lua", "codecompanion", "interactions", "cli", "integrations", integration.script)
  return api.nvim_get_runtime_file(path, false)[1]
end

---@param value any
---@param indent string
---@return string
local function encode(value, indent)
  if type(value) ~= "table" then
    return vim.json.encode(value)
  end

  local child = indent .. "  "

  if vim.islist(value) then
    if vim.tbl_isempty(value) then
      return "[]"
    end
    local items = vim.tbl_map(function(item)
      return child .. encode(item, child)
    end, value)
    return "[\n" .. table.concat(items, ",\n") .. "\n" .. indent .. "]"
  end

  if vim.tbl_isempty(value) then
    return "{}"
  end

  -- Decoding loses the original key order, so sort to keep repeat writes stable
  local keys = vim.tbl_keys(value)
  table.sort(keys)

  local pairs_out = vim.tbl_map(function(key)
    return string.format("%s%s: %s", child, vim.json.encode(key), encode(value[key], child))
  end, keys)

  return "{\n" .. table.concat(pairs_out, ",\n") .. "\n" .. indent .. "}"
end

---@param path string
---@return table|nil settings Nil when the file could not be parsed
local function read_settings(path)
  local contents = table.concat(vim.fn.readfile(path), "\n")
  if vim.trim(contents) == "" then
    return {}
  end

  local ok, decoded = pcall(vim.json.decode, contents, { luanil = { object = true, array = true } })
  if not ok or type(decoded) ~= "table" then
    return nil
  end

  return decoded
end

---Drop the entries a previous install wrote, leaving the user's own hooks in place
---@param entries table[]
---@return table[]
local function without_ours(entries)
  return vim.tbl_filter(function(entry)
    for _, hook in ipairs(entry.hooks or {}) do
      if type(hook.command) == "string" and hook.command:find(CONSTANTS.MARKER, 1, true) then
        return false
      end
    end
    return true
  end, entries)
end

---@param action string
---@return table
local function build_entry(action)
  return {
    hooks = {
      {
        type = "command",
        command = string.format('[ -z "%s" ] || "%s" %s', CONSTANTS.MARKER, CONSTANTS.MARKER, action),
      },
    },
  }
end

---@param integration CodeCompanion.CLI.Hooks.Integration
---@return string
local function settings_path(integration)
  return vim.fs.joinpath(vim.fn.expand("~"), integration.settings)
end

---@param integration CodeCompanion.CLI.Hooks.Integration
---@return boolean
local function install(integration)
  local path = settings_path(integration)

  local settings = read_settings(path)
  if not settings then
    utils.notify(string.format("Could not parse %s, so it has been left alone", path), vim.log.levels.ERROR)
    return false
  end

  settings.hooks = settings.hooks or {}
  for event, action in pairs(integration.hooks) do
    local entries = without_ours(settings.hooks[event] or {})
    table.insert(entries, build_entry(action))
    settings.hooks[event] = entries
  end

  local ok, err = pcall(files.write_to_path, path, encode(settings, "") .. "\n")
  if not ok then
    utils.notify(string.format("Could not write %s: %s", path, err), vim.log.levels.ERROR)
    return false
  end

  return true
end

---@return CodeCompanion.CLI.Hooks.Integration[]
local function configured_integrations()
  local found = {}

  for _, agent in pairs(config.interactions.cli.agents or {}) do
    local integration = agent.cmd and INTEGRATIONS[vim.fs.basename(agent.cmd)]
    if integration and not vim.tbl_contains(found, integration) then
      table.insert(found, integration)
    end
  end

  return found
end

---Write the hooks each configured CLI agent needs in order to report its turns
---@return nil
function M.install()
  local integrations = configured_integrations()
  if vim.tbl_isempty(integrations) then
    return utils.notify("None of your CLI agents have an integration", vim.log.levels.WARN)
  end

  -- An agent that has never run has no settings to merge into, and writing its config for it
  -- would leave a file the agent itself has never validated
  local ready = vim.tbl_filter(function(integration)
    if files.exists(settings_path(integration)) then
      return true
    end
    utils.notify(
      string.format("%s was not found, so run %s once first", settings_path(integration), integration.name),
      vim.log.levels.WARN
    )
    return false
  end, integrations)

  if vim.tbl_isempty(ready) then
    return
  end

  local targets = vim.tbl_map(settings_path, ready)
  local prompt = string.format("Add CodeCompanion's hooks to:\n%s", table.concat(targets, "\n"))
  if vim.fn.confirm(prompt, "&Install\n&Cancel", 2) ~= 1 then
    return
  end

  for _, integration in ipairs(ready) do
    if install(integration) then
      utils.notify(string.format("Installed the %s hooks", integration.name))
    end
  end
end

return M
