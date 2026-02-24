local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local mcp = require("codecompanion.mcp")
local utils = require("codecompanion.utils")

local fmt = string.format

local CONSTANTS = {
  NAME = "MCP",
  PROMPT = "Toggle MCP server",
  STARTED_ICON = "",
  STOPPED_ICON = "○",
}

---Build picker entries for configured MCP servers
---@return table[]
local function build_items()
  local items = {}
  local status = mcp.get_status()

  for name, server in pairs(status) do
    local icon = server.started and CONSTANTS.STARTED_ICON or CONSTANTS.STOPPED_ICON
    local activity = server.started and (server.ready and "ready" or "starting") or "stopped"
    local display = fmt("%s %s (%s, tools: %d)", icon, name, activity, server.tool_count or 0)

    table.insert(items, {
      default = server.default,
      name = name,
      display = display,
      text = display,
    })
  end

  return items
end

---Toggle the selected MCP server
---@param selected { name: string }
---@return nil
local function toggle_server(selected)
  local ok, result = mcp.toggle_server(selected.name)
  if not ok then
    return log:warn(result)
  end

  local status = mcp.get_status()[selected.name]
  local state = status and status.started and "started" or "stopped"
  utils.notify(fmt("MCP server `%s` %s", selected.name, state))
end

local providers = {
  ---The default provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  default = function(SlashCommand)
    local items = build_items()
    if #items == 0 then
      return utils.notify("No MCP servers configured", vim.log.levels.WARN)
    end

    vim.ui.select(items, {
      kind = "codecompanion.nvim",
      prompt = CONSTANTS.PROMPT,
      format_item = function(item)
        return item.display
      end,
    }, function(selected)
      if not selected then
        return
      end
      return SlashCommand:output(selected)
    end)
  end,

  ---The Snacks.nvim provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  snacks = function(SlashCommand)
    local items = build_items()
    if #items == 0 then
      return utils.notify("No MCP servers configured", vim.log.levels.WARN)
    end

    local snacks = require("codecompanion.providers.slash_commands.snacks")
    snacks = snacks.new({
      title = CONSTANTS.PROMPT .. ": ",
      output = function(selection)
        return SlashCommand:output(selection)
      end,
    })

    snacks.provider.picker.pick({
      title = CONSTANTS.PROMPT,
      items = items,
      prompt = snacks.title,
      format = function(item, _)
        return { { item.display } }
      end,
      confirm = snacks:display(),
      main = { file = false, float = true },
    })
  end,
}

---@class CodeCompanion.SlashCommand.MCP: CodeCompanion.SlashCommand
local SlashCommand = {}

---@param args CodeCompanion.SlashCommandArgs
function SlashCommand.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommand })

  return self
end

---Is the slash command enabled?
---@return boolean|boolean,string
function SlashCommand.enabled()
  if vim.tbl_isempty(config.mcp.servers or {}) then
    return false, "[MCP] No servers found in your configuration"
  end
  return true
end

---Execute the slash command
---@param SlashCommands CodeCompanion.SlashCommands
---@return nil
function SlashCommand:execute(SlashCommands)
  return SlashCommands:set_provider(self, providers)
end

---Output from the slash command in the chat buffer
---@param selected { name: string }
---@return nil
function SlashCommand:output(selected)
  return toggle_server(selected)
end

return SlashCommand
