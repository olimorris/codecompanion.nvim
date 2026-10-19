local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local mcp = require("codecompanion.mcp")
local picker = require("codecompanion.providers.slash_commands.picker")
local utils = require("codecompanion.utils")

local fmt = string.format

local CONSTANTS = {
  NAME = "MCP",
  PROMPT = "Toggle MCP servers",
  STARTED_ICON = "",
  STOPPED_ICON = "○",
}

---List configured servers and registered tool groups
---@return CodeCompanion.SlashCommand.PickerItem[]
local function list_servers()
  local items = {}
  local status = mcp.get_status()
  local _, registered_groups = mcp.get_registered_tools()

  for name, server in pairs(status) do
    local icon = server.started and CONSTANTS.STARTED_ICON or CONSTANTS.STOPPED_ICON
    local activity = server.started and (server.ready and "ready" or "starting") or "stopped"
    table.insert(items, {
      name = fmt("%s %s", icon, name),
      description = fmt("%s, tools: %d", activity, server.tool_count or 0),
      server = name,
      type = "configured",
    })
  end

  for group_name, group in pairs(registered_groups) do
    local server_name = group_name:sub(#mcp.tool_prefix() + 1)
    if not status[server_name] then
      table.insert(items, {
        name = fmt("%s %s", CONSTANTS.STARTED_ICON, server_name),
        description = fmt("registered, tools: %d", #group.tools),
        server = server_name,
        group = group_name,
        type = "registered",
      })
    end
  end

  table.sort(items, function(a, b)
    return a.server < b.server
  end)

  return items
end

---@param selected { server: string }
---@return nil
local function toggle_server(selected)
  local ok, result = mcp.toggle_server(selected.server)
  if not ok then
    return log:warn(result)
  end

  local status = mcp.get_status()[selected.server]
  local state = status and status.started and "started" or "stopped"
  utils.notify(fmt("MCP server `%s` %s", selected.server, state))
end

---@param selected { server: string, group: string }
---@param opts { chat: CodeCompanion.Chat }
---@return nil
local function add_registered_group(selected, opts)
  local chat = opts.chat
  chat.tools:refresh({ adapter = chat.adapter })

  if not chat.tool_registry:add(selected.group, { config = chat.tools.tools_config }) then
    return utils.notify(fmt("MCP server `%s` is already enabled", selected.server))
  end

  utils.notify(fmt("MCP server `%s` enabled", selected.server))
end

local providers = picker.build_list_pickers({
  prompt = CONSTANTS.PROMPT,
  empty_message = "No MCP servers configured",
  preview = false,
  items = list_servers,
})

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
  local _, registered_groups = mcp.get_registered_tools()
  if vim.tbl_isempty(config.mcp.servers or {}) and vim.tbl_isempty(registered_groups) then
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
---@param selected { server: string, type: string, group?: string }
---@return nil
function SlashCommand:output(selected)
  if selected.type == "registered" then
    return add_registered_group(selected, { chat = self.Chat })
  end

  return toggle_server(selected)
end

return SlashCommand
