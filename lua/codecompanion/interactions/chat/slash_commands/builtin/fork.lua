local config = require("codecompanion.config")
local utils = require("codecompanion.utils")

---@class CodeCompanion.SlashCommand.Fork
---@field Chat CodeCompanion.Chat
---@field config table
---@field context table
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

function SlashCommand:execute()
  if vim.tbl_isempty(self.Chat.messages) then
    return utils.notify("No messages to fork", vim.log.levels.WARN)
  end

  vim.ui.input({ default = self.Chat.title, prompt = " Fork Title " }, function(name)
    if name == nil then
      return
    end
    self:output(name)
  end)
end

---Fork the current chat into a new chat buffer
---@param name string The name for the forked chat
---@return nil
function SlashCommand:output(name)
  local source = self.Chat

  local messages = vim.deepcopy(source.messages or {})

  -- Append an empty user message so that the chat starts with user input
  table.insert(messages, {
    content = "",
    role = config.constants.USER_ROLE,
  })

  local title = (name ~= "") and name or ("Fork of: " .. (source.title or ("Chat " .. source.id)))

  local Chat = require("codecompanion.interactions.chat")
  local forked = Chat.new({
    adapter = source.adapter,
    last_role = config.constants.USER_ROLE,
    messages = messages,
    settings = source.settings and vim.deepcopy(source.settings) or nil,
    stop_context_insertion = true,
    title = title,
  })

  -- This ensures we respect any conditionals on the chat class
  if not forked then
    return
  end

  forked:set_title(forked.title) -- Needed for description as well

  local context_items = vim.deepcopy(source.context_items or {})
  if not vim.tbl_isempty(context_items) then
    forked.context_items = context_items
  end

  forked.tool_registry.groups = vim.deepcopy(source.tool_registry.groups)
  forked.tool_registry.in_use = vim.deepcopy(source.tool_registry.in_use)
  forked.tool_registry.schemas = vim.deepcopy(source.tool_registry.schemas)

  forked.context:render()
end

return SlashCommand
