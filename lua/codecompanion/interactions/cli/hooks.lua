local config = require("codecompanion.config")
local files = require("codecompanion.utils.files")
local utils = require("codecompanion.utils")

local api = vim.api

local M = {}

---@class CodeCompanion.CLI.Integration
---@field name string
---@field script string Filename beneath `interactions/cli/integrations/`
---@field get_settings_path fun(): string
---@field install fun(): boolean, string|nil

---An agent's integration, which is named after the command that starts it
---@param cmd string
---@return CodeCompanion.CLI.Integration|nil
local function get_integration(cmd)
  local ok, integration = pcall(require, "codecompanion.interactions.cli.integrations." .. vim.fs.basename(cmd))
  if not ok then
    return nil
  end

  return integration
end

---@return CodeCompanion.CLI.Integration[]
local function get_configured_integrations()
  local found = {}

  for _, agent in pairs(config.interactions.cli.agents or {}) do
    local integration = agent.cmd and get_integration(agent.cmd)
    if integration and not vim.tbl_contains(found, integration) then
      table.insert(found, integration)
    end
  end

  return found
end

---Write the hooks each configured CLI agent needs in order to report its turns
---@return nil
function M.install()
  local integrations = get_configured_integrations()
  if vim.tbl_isempty(integrations) then
    return utils.notify("None of your CLI agents have an integration", vim.log.levels.WARN)
  end

  -- An agent that has never run has no settings to merge into, so check for this
  local ready = vim.tbl_filter(function(integration)
    if files.exists(integration.get_settings_path()) then
      return true
    end
    utils.notify(
      string.format("%s was not found, so run %s once first", integration.get_settings_path(), integration.name),
      vim.log.levels.WARN
    )
    return false
  end, integrations)

  if vim.tbl_isempty(ready) then
    return
  end

  local targets = vim.tbl_map(function(integration)
    return integration.get_settings_path()
  end, ready)

  local prompt = string.format("Add CodeCompanion's hooks to:\n%s", table.concat(targets, "\n"))
  if vim.fn.confirm(prompt, "&Install\n&Cancel", 2) ~= 1 then
    return
  end

  for _, integration in ipairs(ready) do
    local ok, err = integration.install()
    if ok then
      utils.notify(string.format("Installed the %s hooks", integration.name))
    else
      utils.notify(err, vim.log.levels.ERROR)
    end
  end
end

---The script an agent's hooks call
---@param cmd string
---@return string|nil
function M.script_for_agent(cmd)
  local integration = get_integration(cmd)
  if not integration then
    return nil
  end

  local path = vim.fs.joinpath("lua", "codecompanion", "interactions", "cli", "integrations", integration.script)
  return api.nvim_get_runtime_file(path, false)[1]
end

return M
