local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local slash_commands = require("codecompanion.strategies.chat.slash_commands")
local util = require("codecompanion.utils")

local fmt = string.format

local CONSTANTS = {
  NAME = "Workspace",
  PROMPT = "Select a workspace group",
  WORKSPACE_FILE = vim.fs.joinpath(vim.fn.getcwd(), "codecompanion-workspace.json"),
}

---Replace variables in a string
---@param workspace table
---@param group table
---@param str string
---@return string
local function replace_vars(workspace, group, str)
  local replaced_vars = {}

  -- Vars from the top level can be overwritten, so they come first
  if workspace.vars then
    vim.iter(workspace.vars):each(function(k, v)
      replaced_vars[k] = v
    end)
  end

  if group.vars then
    vim.iter(group.vars):each(function(k, v)
      replaced_vars[k] = v
    end)
  end

  -- Add the builtin group level and workspace vars
  replaced_vars["workspace_name"] = workspace.name
  replaced_vars["group_name"] = group.name

  return util.replace_placeholders(str, replaced_vars)
end

---Add the description of the group to the chat buffer
---@param chat CodeCompanion.Chat
---@param workspace table
---@param group { name: string, description: string, files: table?, symbols: table? }
local function add_group_description(chat, workspace, group)
  chat:add_message({
    role = config.constants.USER_ROLE,
    content = replace_vars(workspace, group, group.description),
  }, { visible = false })
end

---@class CodeCompanion.SlashCommand.Workspace: CodeCompanion.SlashCommand
local SlashCommand = {}

---@param args CodeCompanion.SlashCommandArgs
function SlashCommand.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
    opts = args.opts or {},
  }, { __index = SlashCommand })

  self.workspace = {}

  return self
end

---Open and read the contents of the workspace file
---@param path? string
---@return table
function SlashCommand:read_workspace_file(path)
  if not path then
    path = CONSTANTS.WORKSPACE_FILE
  end
  if not path then
    path = vim.fs.joinpath(vim.fn.getcwd(), "codecompanion-workspace.json")
    CONSTANTS.WORKSPACE_FILE = vim.fs.joinpath(vim.fn.getcwd(), "codecompanion-workspace.json")
  end

  if not vim.uv.fs_stat(path) then
    return log:warn(fmt("Could not find a workspace file at `%s`", path))
  end

  local short_path = vim.fn.fnamemodify(path, ":t")

  -- Read the file
  local content
  local f = io.open(path, "r")
  if f then
    content = f:read("*a")
    f:close()
  end
  if content == "" or content == nil then
    return log:warn(fmt("No content to read in the `%s` file", short_path))
  end

  -- Parse the JSON
  local ok, json = pcall(function()
    return vim.json.decode(content)
  end)
  if not ok then
    return log:error(fmt("Invalid JSON in the `%s` file", short_path))
  end

  return json
end

---Add an item from the data section to the chat buffer
---@param group table
---@param item string
function SlashCommand:add_to_chat(group, item)
  local resource = self.workspace.data[item]
  if not resource then
    return log:warn("Could not find '%s' in the workspace file", item)
  end

  -- Apply group variables to path
  local path = replace_vars(self.workspace, group, resource.path)

  -- Apply built-in variables to description
  local description = resource.description
  if description then
    local builtin = {
      cwd = vim.fn.getcwd(),
      filename = vim.fn.fnamemodify(path, ":t"),
      path = path,
    }
    -- Replace variables from the user's custom declarations as well as the builtin ones
    description = util.replace_placeholders(replace_vars(self.workspace, group, description), builtin)
  end

  -- Extract options if present
  local opts = resource.opts or {}

  return slash_commands.references(self.Chat, resource.type, { path = path, description = description, opts = opts })
end

---Execute the slash command
---@param SlashCommands CodeCompanion.SlashCommands
---@param opts? table
---@return nil
function SlashCommand:execute(SlashCommands, opts)
  if not config.can_send_code() and (self.config.opts and self.config.opts.contains_code) then
    return log:warn("Sending of code has been disabled")
  end

  self.workspace = self:read_workspace_file()

  -- Get the group names
  local groups = {}
  vim.iter(self.workspace.groups):each(function(group)
    table.insert(groups, group.name)
  end)
  --TODO: Add option to add all groups
  -- if vim.tbl_count(groups) > 1 then
  --   table.insert(groups, 1, "All")
  -- end

  -- Let the user select a group
  vim.ui.select(groups, { kind = "codecompanion.nvim", prompt = "Select a Group to load" }, function(choice)
    if not choice then
      return nil
    end

    return self:output(choice, opts)
  end)
end

---Add the selected group to the chat buffer
---@param selected_group string
---@param opts? table
function SlashCommand:output(selected_group, opts)
  local group = vim.tbl_filter(function(g)
    return g.name == selected_group
  end, self.workspace.groups)[1]

  if group.opts then
    if group.opts.remove_config_system_prompt then
      self.Chat:remove_tagged_message("from_config")
    end
  end

  -- Add the system prompts
  if self.workspace.system_prompt then
    self.Chat:add_system_prompt(
      replace_vars(self.workspace, group, self.workspace.system_prompt),
      { visible = false, tag = self.workspace.name .. " // Workspace" }
    )
  end

  if group.system_prompt then
    self.Chat:add_system_prompt(
      replace_vars(self.workspace, group, group.system_prompt),
      { visible = false, tag = group.name .. " // Workspace Group" }
    )
  end

  -- Add the description as a user message
  if group.description then
    add_group_description(self.Chat, self.workspace, group)
  end

  if group.data and self.workspace.data then
    for _, data_item in ipairs(group.data) do
      self:add_to_chat(group, data_item)
    end
  end
end

return SlashCommand
