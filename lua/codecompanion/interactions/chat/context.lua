local config = require("codecompanion.config")

local api = vim.api
local query_get = vim.treesitter.query.get --[[@as function]]

local icons = {
  sync_all = config.display.chat.icons.sync_all,
  sync_diff = config.display.chat.icons.sync_diff,
}

local allowed__all = {
  "<buf>",
  "<file>",
}
local allowed__diff = {
  "<buf>",
  "<file>",
}
local context_header = "> Context:"

---Whether attached content at this path is watched for changes out of the box
---@param path? string
---@return boolean
local function syncs_by_default(path)
  local extensions = config.interactions.chat.opts.sync_diff
  if not path or type(extensions) ~= "table" then
    return false
  end

  local extension = path:match("%.([^.]+)$")
  return extension ~= nil and extensions[extension:lower()] == true
end

---@param context CodeCompanion.Chat.ContextItem
---@return string
local function format_item(context)
  if context.opts and context.opts.sync_all then
    return string.format("> - %s%s", icons.sync_all, context.id)
  elseif context.opts and context.opts.sync_diff then
    return string.format("> - %s%s", icons.sync_diff, context.id)
  end
  return string.format("> - %s", context.id)
end

---Strip the list marker and sync icons from a rendered context item
---@param line string
---@return string
local function get_item_id(line)
  return vim.trim(vim.iter(vim.tbl_values(icons)):fold(select(1, line:gsub("^> %- ", "")), function(acc, icon)
    return select(1, acc:gsub(icon, ""))
  end))
end

---@class CodeCompanion.Chat.ContextItem
---@field bufnr? number The buffer number if this is buffer context
---@field id string The unique ID of the context which links it to a message in the chat buffer and is displayed to the user
---@field path? string The path of the file or buffer this context was created from
---@field source string The source of the context e.g. slash_command
---@field opts? table
---@field opts.sync_all? boolean When synced, whether all of the content is shared
---@field opts.sync_diff? boolean When synced, whether only diffs are shared. Defaults from `opts.sync_diff` in the chat config
---@field opts.visible? boolean Whether this context item should be shown in the chat UI

---@class CodeCompanion.Chat.Context
---@field Chat CodeCompanion.Chat
local Context = {}

---The header the rendered context block is written under
Context.HEADER = context_header

---@class CodeCompanion.Chat.ContextArgs
---@field chat CodeCompanion.Chat

---@param args CodeCompanion.Chat.ContextArgs
function Context.new(args)
  local self = setmetatable({
    Chat = args.chat,
  }, { __index = Context })

  return self
end

---Add context to the chat buffer
---@param context CodeCompanion.Chat.ContextItem
---@return nil
function Context:add(context)
  if not context or not config.display.chat.show_context then
    return self
  end

  if context then
    context.opts = context.opts or {}

    -- Ensure both properties exist with defaults
    context.opts.sync_all = context.opts.sync_all or false
    if context.opts.sync_diff == nil then
      context.opts.sync_diff = not context.opts.sync_all and syncs_by_default(context.path)
    end
    context.opts.visible = context.opts.visible

    if context.opts.visible == nil then
      context.opts.visible = config.display.chat.show_context
    end

    -- Prevent duplicate context items with the same id
    if context.id then
      for _, existing in ipairs(self.Chat.context_items) do
        if existing.id == context.id then
          return self
        end
      end
    end

    table.insert(self.Chat.context_items, context)
    if context.opts.sync_diff then
      local synced = false
      if context.bufnr then
        synced = self.Chat.watchers:sync_buffer({ id = context.id, bufnr = context.bufnr })
      elseif context.path then
        synced = self.Chat.watchers:sync_file({ id = context.id, path = context.path })
      end
      context.opts.sync_diff = synced
    end
  end

  if context.opts.visible then
    self.Chat.prompt:add_context({ line = format_item(context) })
  end
end

---Remove any context items from a message in the chat buffer before submission
---@param message table
---@return table
function Context:remove(message)
  if vim.tbl_isempty(self.Chat.context_items) or not config.display.chat.show_context then
    return message or nil
  end

  local parser = vim.treesitter.get_string_parser(message.content, "markdown")
  local query = query_get("markdown", "cc_context")
  local root = parser:parse()[1]:root()

  local items = nil
  for id, node in query:iter_captures(root, message.content) do
    if query.captures[id] == "context" then
      items = node
    end
  end

  if items then
    local start_row, _, end_row, _ = items:range()
    message.content = vim.split(message.content, "\n")
    for i = start_row, end_row do
      message.content[i] = ""
    end
    message.content = vim.trim(table.concat(message.content, "\n"))
  end

  return message
end

---Render all the context items in the chat buffer after a response from the LLM
---@return nil
function Context:render()
  local chat = self.Chat
  if vim.tbl_isempty(chat.context_items) then
    return self
  end

  local lines = { context_header }

  for _, context in pairs(chat.context_items) do
    if context and not (context.opts and context.opts.visible == false) then
      table.insert(lines, format_item(context))
    end
  end
  if #lines == 1 then
    return
  end

  chat.prompt:render_context({ lines = lines })
end

---Clear the rendered context block from the chat buffer (if present)
---@return CodeCompanion.Chat.Context
function Context:clear_rendered()
  self.Chat.prompt:clear_context()
  return self
end

---Remove context items by their IDs and re-render the context block
---@param ids table<string, boolean> A set of IDs to remove
---@return nil
function Context:remove_items(ids)
  self.Chat.context_items = vim
    .iter(self.Chat.context_items)
    :filter(function(ctx)
      return not ids[ctx.id]
    end)
    :totable()

  if self.Chat.bufnr and api.nvim_buf_is_valid(self.Chat.bufnr) then
    self:clear_rendered()
    self:render()
  end
end

---Make a unique ID from the buffer number
---@param bufnr number
---@return string
function Context:make_id_from_buf(bufnr)
  return vim.fn.fnamemodify(api.nvim_buf_get_name(bufnr), ":.")
end

---Determine if a context item can be synced and all of its content shared
---@param item string
---@return boolean
function Context:can_be_synced__all(item)
  for _, sync in ipairs(allowed__all) do
    if item:find(sync) then
      return true
    end
  end
  return false
end

---Determine if a context item can be synced and its diff shared
---@param item string
---@return boolean
function Context:can_be_synced__diff(item)
  for _, sync in ipairs(allowed__diff) do
    if item:find(sync) then
      return true
    end
  end
  return false
end

---Get the context items from the chat buffer
---@return table
function Context:get_from_chat()
  return vim.tbl_map(get_item_id, self.Chat.prompt:get_context())
end

return Context
