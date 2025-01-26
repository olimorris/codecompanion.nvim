local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local slash_commands = require("codecompanion.strategies.chat.slash_commands")
local util = require("codecompanion.utils")

local fmt = string.format

CONSTANTS = {
  NAME = "Workspace",
  PROMPT = "Select a workspace group",
  WORKSPACE_FILE = vim.fs.joinpath(vim.fn.getcwd(), "codecompanion-workspace.json"),
}

---Output a list of files in the group
---@return string
local function get_file_list(group)
  local items = {}

  if group.files then
    vim.iter(group.files):each(function(file)
      table.insert(items, "- " .. (file.path or file))
    end)
  end
  if group.symbols then
    vim.iter(group.symbols):each(function(symbol)
      table.insert(items, "- " .. (symbol.path or symbol))
    end)
  end

  if vim.tbl_count(items) == 0 then
    return ""
  end

  if group.vars then
    util.replace_placeholders(items, group.vars)
  end

  return table.concat(items, "\n")
end

---Add the description of the group to the chat buffer
---@param chat CodeCompanion.Chat
---@param workspace table
---@param group { name: string, description: string, files: table?, symbols: table? }
local function add_group_description(chat, workspace, group)
  local builtin = {
    group_name = group.name,
    group_list = get_file_list(group),
    workspace_description = workspace.description,
    workspace_name = workspace.name,
  }

  local description = util.replace_placeholders(group.description, builtin)

  chat:add_message({
    role = config.constants.USER_ROLE,
    content = description,
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
    workspace = args.workspace or {},
    opts = args.opts,
  }, { __index = SlashCommand })

  return self
end

---Open and read the contents of the workspace file
---@param path? string
---@return table
function SlashCommand:read_workspace_file(path)
  if not path then
    path = CONSTANTS.WORKSPACE_FILE
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
  vim.ui.select(groups, { prompt = "Select a Group to load" }, function(choice)
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

  --TODO: Account for all groups

  add_group_description(self.Chat, self.workspace, group)

  -- Add files
  if group.files and vim.tbl_count(group.files) > 0 then
    vim.iter(group.files):each(function(file)
      self:add_item(group, "file", file)
    end)
  end

  -- Add symbols
  if group.symbols and vim.tbl_count(group.symbols) > 0 then
    vim.iter(group.symbols):each(function(file)
      self:add_item(group, "symbols", file)
    end)
  end
end

---Add an item from the group to the chat buffer
---@param group table
---@param item_type string
---@param item { path: string, description: string } | string
function SlashCommand:add_item(group, item_type, item)
  -- Replace any variables in the path
  local path = item.path or item
  if group.vars then
    path = util.replace_placeholders(path, group.vars)
  end

  -- Replace any built-in variables
  local builtin = {
    cwd = vim.fn.getcwd(),
    filename = vim.fn.fnamemodify(path, ":t"),
    path = path,
  }
  if item.description then
    item.description = util.replace_placeholders(item.description, builtin)
  end

  return slash_commands.references(self.Chat, item_type, { path = path, description = item.description })
end

return SlashCommand
