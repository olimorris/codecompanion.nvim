--[[
Methods for handling interactions between the chat buffer and tools
--]]

---@class CodeCompanion.Chat.ToolRegistry
---@field chat CodeCompanion.Chat
---@field flags table Flags that external functions can update and subscribers can interact with
---@field groups table<string, string[]> Groups and their member tool names
---@field in_use table<string, boolean> Tools that are in use on the chat buffer
---@field schemas table<string, table> The config for the tools in use

---@class CodeCompanion.Chat.ToolRegistry
local ToolRegistry = {}

local config = require("codecompanion.config")
local utils = require("codecompanion.utils")

local fmt = string.format

---Make a tool ID from a tool name
---@param name string
---@return string
local function tool_id(name)
  return fmt("<tool>%s</tool>", name)
end

---Make a group ID from a group name
---@param name string
---@return string
local function group_id(name)
  return fmt("<group>%s</group>", name)
end

---@class CodeCompanion.Chat.ToolsArgs
---@field chat CodeCompanion.Chat

---@param args CodeCompanion.Chat.ToolsArgs
function ToolRegistry.new(args)
  local self = setmetatable({
    chat = args.chat,
    flags = {},
    groups = {},
    in_use = {},
    schemas = {},
  }, { __index = ToolRegistry })

  return self
end

---Add context about the tool in the chat buffer
---@param chat CodeCompanion.Chat The chat buffer
---@param id string The id of the tool
---@param opts? table Optional parameters for the context_item
---@return nil
local function add_context(chat, id, opts)
  chat.context:add({
    source = "tool",
    name = "tool",
    id = id,
    opts = opts,
  })
end

---Add the tool's system prompt to the chat buffer
---@param chat CodeCompanion.Chat The chat buffer
---@param tool table the resolved tool
---@param id string The id of the tool
---@return nil
local function add_system_prompt(chat, tool, id)
  if tool and tool.system_prompt then
    local system_prompt
    if type(tool.system_prompt) == "function" then
      system_prompt = tool.system_prompt(tool.schema)
    elseif type(tool.system_prompt) == "string" then
      system_prompt = tostring(tool.system_prompt)
    end
    chat:add_message(
      { role = config.constants.SYSTEM_ROLE, content = system_prompt },
      { visible = false, _meta = { tag = "tool" }, context = { id = id } }
    )
  end
end

---Add the tool's schema to the chat buffer
---@param self CodeCompanion.Chat.ToolRegistry The registry object
---@param tool table The resolved tool
---@param id string The id of the tool
---@return nil
local function add_schema(self, tool, id)
  self.schemas[id] = tool.schema
end

---Add a tool or group to the chat buffer
---@param name string The name of the tool or group
---@param opts? { config: table, visible: boolean }
---@return CodeCompanion.Chat.ToolRegistry|nil
function ToolRegistry:add(name, opts)
  opts = opts or {}

  local tools_config = opts.config or config.interactions.chat.tools

  if tools_config.groups and tools_config.groups[name] then
    return self:add_group(name, { config = tools_config })
  end

  local tool_config = tools_config[name]
  if tool_config then
    return self:add_single_tool(name, { config = tool_config, visible = opts.visible })
  end

  return nil
end

---Add a single tool to the chat buffer
---@param tool string The name of the tool
---@param opts? { config: table, visible: boolean }
---@return CodeCompanion.Chat.ToolRegistry|nil
function ToolRegistry:add_single_tool(tool, opts)
  opts = opts or {}
  if opts.visible == nil then
    opts.visible = true
  end

  local tool_config = opts.config or config.interactions.chat.tools[tool]
  if not tool_config then
    return nil
  end

  if self.in_use[tool] then
    return nil
  end

  local id = tool_id(tool)

  local is_adapter_tool = tool_config._adapter_tool == true
  if is_adapter_tool then
    add_context(self.chat, id, opts)
    add_schema(self, {
      schema = {
        name = tool,
        description = tool_config.description or "",
        _meta = {
          adapter_tool = true,
        },
      },
    }, id)
  else
    local resolved_tool = self.chat.tools.resolve(tool_config)
    if not resolved_tool then
      return nil
    end

    add_context(self.chat, id, opts)
    add_system_prompt(self.chat, resolved_tool, id)
    add_schema(self, resolved_tool, id)
    self:add_tool_system_prompt()
  end

  utils.fire("ChatToolAdded", { bufnr = self.chat.bufnr, id = self.chat.id, tool = tool })
  self.in_use[tool] = true

  return self
end

---Add tools from a group to the chat buffer
---@param group string The name of the group
---@param opts? { config: table }
---@return CodeCompanion.Chat.ToolRegistry|nil
function ToolRegistry:add_group(group, opts)
  opts = opts or {}

  if self.groups[group] then
    return nil
  end

  local tools_config = opts.config or config.interactions.chat.tools
  local group_config = tools_config.groups[group]
  if not group_config or not group_config.tools then
    return nil
  end

  local group_opts = vim.tbl_deep_extend("force", { collapse_tools = true }, group_config.opts or {})
  local collapse_tools = group_opts.collapse_tools

  local gid = group_id(group)

  if group_opts.ignore_system_prompt then
    self.chat:remove_tagged_message("system_prompt_from_config")
    self.flags.ignore_system_prompt = true
  end

  if group_opts.ignore_tool_system_prompt then
    self.chat:remove_tagged_message("tool_system_prompt")
    self.flags.ignore_tool_system_prompt = true
  end

  local system_prompt = group_config.system_prompt
  if type(system_prompt) == "function" then
    system_prompt = system_prompt(group_config, self.chat:make_system_prompt_ctx())
  end
  if system_prompt then
    self.chat:add_message({
      role = config.constants.SYSTEM_ROLE,
      content = system_prompt,
    }, { _meta = { tag = "tool" }, context = { id = gid }, visible = false })
  end

  if collapse_tools then
    add_context(self.chat, gid)
  end
  local added_tools = {}
  for _, tool in ipairs(group_config.tools) do
    local tool_cfg = tools_config[tool]
    if tool_cfg then
      if self:add_single_tool(tool, { config = tool_cfg, visible = not collapse_tools }) then
        table.insert(added_tools, tool)
      end
    end
  end
  self.groups[group] = added_tools

  return self
end

---Add a tool system prompt to the chat buffer, updated for every tool addition
---@return nil
function ToolRegistry:add_tool_system_prompt()
  if self.flags.ignore_tool_system_prompt then
    return
  end

  local opts = config.interactions.chat.tools.opts.system_prompt or {}
  if not opts.enabled then
    return
  end

  local prompt = opts.prompt
  if type(prompt) == "function" then
    prompt = prompt({ tools = vim.tbl_keys(self.in_use) })
  end

  local index = 2 -- Add after the main system prompt if not replacing
  if opts.replace_main_system_prompt then
    index = 1
    self.chat:remove_tagged_message("system_prompt_from_config")
  end

  self.chat:set_system_prompt(prompt, { visible = false, _meta = { tag = "tool_system_prompt", index = index } })
end

---Determine if the chat buffer has any tools in use
---@return boolean
function ToolRegistry:loaded()
  return not vim.tbl_isempty(self.in_use)
end

---Remove a named group and its member tools from the registry. Also cleans up all artifacts
---@param name string The group name to remove
---@return nil
function ToolRegistry:remove_group(name)
  local tool_names = self.groups[name]
  if not tool_names then
    return
  end

  local to_remove = {}
  to_remove[group_id(name)] = true

  for _, tool_name in ipairs(tool_names) do
    local id = tool_id(tool_name)
    to_remove[id] = true
    self.in_use[tool_name] = nil
    self.schemas[id] = nil
  end
  self.groups[name] = nil

  self.chat.context:remove_items(to_remove)

  self.chat.messages = vim
    .iter(self.chat.messages)
    :filter(function(msg)
      if msg._meta and msg._meta.tag == "tool" and msg.context and to_remove[msg.context.id] then
        return false
      end
      return true
    end)
    :totable()

  if self.flags.ignore_system_prompt then
    self.flags.ignore_system_prompt = nil
    self.chat:set_system_prompt()
  end
  if self.flags.ignore_tool_system_prompt then
    self.flags.ignore_tool_system_prompt = nil
  end

  if vim.tbl_isempty(self.in_use) then
    self.chat:remove_tagged_message("tool_system_prompt")
  else
    self:add_tool_system_prompt()
  end
end

---Clear the tools
---@return nil
function ToolRegistry:clear()
  self.flags = {}
  self.groups = {}
  self.in_use = {}
  self.schemas = {}
end

return ToolRegistry
