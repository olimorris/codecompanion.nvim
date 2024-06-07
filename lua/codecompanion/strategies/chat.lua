local client = require("codecompanion.client")
local config = require("codecompanion").config
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local schema = require("codecompanion.schema")
local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils.util")
local yaml = require("codecompanion.utils.yaml")

local api = vim.api

local yaml_query = [[
(
  block_mapping_pair
  key: (_) @key
  value: (_) @value
)
]]

local chat_query = [[
(
  atx_heading
  (atx_h1_marker)
  heading_content: (_) @role
)
(
  section
  [(paragraph) (fenced_code_block) (list)] @text
)
]]

local tool_query = [[
(
 (section
  (fenced_code_block
    (info_string) @lang
    (code_fence_content) @tools
  ) (#match? @lang "xml"))
)
]]

---@return CodeCompanion.Adapter|nil
local function resolve_adapter()
  local adapter = config.adapters[config.strategies.chat]

  if type(adapter) == "string" then
    local resolved = require("codecompanion.adapters").use(adapter)
    if not resolved then
      return nil
    end

    return resolved
  end

  return adapter
end

local _cached_settings = {}
---@param bufnr integer
---@param adapter CodeCompanion.Adapter
---@return table
local function parse_settings(bufnr, adapter)
  if _cached_settings[bufnr] then
    return _cached_settings[bufnr]
  end

  if not config.display.chat.show_settings then
    _cached_settings[bufnr] = adapter:get_default_settings()

    log:debug("Using the settings from the user's config: %s", _cached_settings[bufnr])
    return _cached_settings[bufnr]
  end

  local settings = {}
  local parser = vim.treesitter.get_parser(bufnr, "yaml")

  local query = vim.treesitter.query.parse("yaml", yaml_query)
  local root = parser:parse()[1]:root()
  local captures = {}
  for k, v in pairs(query.captures) do
    captures[v] = k
  end

  for _, match in query:iter_matches(root, bufnr) do
    local key = vim.treesitter.get_node_text(match[captures.key], bufnr)
    local value = vim.treesitter.get_node_text(match[captures.value], bufnr)
    settings[key] = yaml.decode(value)
  end

  return settings or {}
end

---@param bufnr integer
---@return table
local function parse_messages(bufnr)
  local output = {}

  local parser = vim.treesitter.get_parser(bufnr, "markdown")
  local query = vim.treesitter.query.parse("markdown", chat_query)
  local root = parser:parse()[1]:root()

  local captures = {}
  for k, v in pairs(query.captures) do
    captures[v] = k
  end

  local message = {}
  for _, match in query:iter_matches(root, bufnr) do
    if match[captures.role] then
      if not vim.tbl_isempty(message) then
        table.insert(output, message)
        message = { role = "", content = "" }
      end
      message.role = vim.trim(vim.treesitter.get_node_text(match[captures.role], bufnr):lower())
    elseif match[captures.text] then
      local text = vim.trim(vim.treesitter.get_node_text(match[captures.text], bufnr))
      if message.content then
        message.content = message.content .. "\n\n" .. text
      else
        message.content = text
      end
      if not message.role then
        message.role = "user"
      end
    end
  end

  if not vim.tbl_isempty(message) then
    table.insert(output, message)
  end

  return output
end

---@param chat CodeCompanion.Chat
---@return CodeCompanion.Tool|nil
local function parse_tools(chat)
  local assistant_parser = vim.treesitter.get_parser(chat.bufnr, "markdown")
  local assistant_query = vim.treesitter.query.parse(
    "markdown",
    [[
(
  (section
    (atx_heading) @heading
    (#match? @heading "# assistant")
  ) @content
)
  ]]
  )
  local assistant_tree = assistant_parser:parse()[1]

  local assistant_response = {}
  for id, node in assistant_query:iter_captures(assistant_tree:root(), chat.bufnr, 0, -1) do
    local name = assistant_query.captures[id]
    if name == "content" then
      local response = vim.treesitter.get_node_text(node, chat.bufnr)
      table.insert(assistant_response, response)
    end
  end

  local response = assistant_response[#assistant_response]

  local parser = vim.treesitter.get_string_parser(response, "markdown")
  local tree = parser:parse()[1]
  local query = vim.treesitter.query.parse("markdown", tool_query)

  local tools = {}
  for id, node in query:iter_captures(tree:root(), response, 0, -1) do
    local name = query.captures[id]
    if name == "tools" then
      local tool = vim.treesitter.get_node_text(node, response)
      table.insert(tools, tool)
    end
  end

  log:debug("Tools detected: %s", tools)

  --TODO: Parse XML to ensure the STag is <tool>

  if tools and #tools > 0 then
    return require("codecompanion.tools").run(chat, tools[#tools])
  end
end

---@param bufnr integer
local display_tokens = function(bufnr)
  if config.display.chat.show_token_count then
    require("codecompanion.utils.tokens").display_tokens(bufnr)
  end
end

_G.codecompanion_chats = {}
-- _G.codecompanion_win_opts = {}

---@param chat CodeCompanion.Chat
local function set_autocmds(chat)
  local aug = api.nvim_create_augroup("CodeCompanion_" .. chat.id, {
    clear = false,
  })

  local bufnr = chat.bufnr

  -- Submit the chat
  api.nvim_create_autocmd("BufWriteCmd", {
    group = aug,
    buffer = bufnr,
    callback = function()
      if not chat then
        vim.notify("[CodeCompanion.nvim]\nChat session has been deleted", vim.log.levels.ERROR)
      else
        chat:submit()
      end
    end,
  })

  -- Clear the virtual text when the user starts typing
  if util.count(_G.codecompanion_chats) == 0 then
    local insertenter_autocmd
    insertenter_autocmd = api.nvim_create_autocmd("InsertEnter", {
      group = aug,
      buffer = bufnr,
      callback = function()
        local ns_id = api.nvim_create_namespace("CodeCompanionChatVirtualText")
        api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

        api.nvim_del_autocmd(insertenter_autocmd)
      end,
    })
  end

  -- Handle toggling the buffer and chat window
  api.nvim_create_autocmd("User", {
    desc = "Store the current chat buffer",
    group = aug,
    pattern = "CodeCompanionChat",
    callback = function(request)
      if request.data.bufnr ~= bufnr or request.data.action ~= "hide_buffer" then
        return
      end

      _G.codecompanion_last_chat_buffer = chat

      --- Store a snapshot of the chat in the global table
      if _G.codecompanion_chats[bufnr] == nil then
        local description
        local messages = parse_messages(bufnr)

        if messages[1] and messages[1].content then
          description = messages[1].content
        else
          description = "[No messages]"
        end

        _G.codecompanion_chats[bufnr] = {
          name = "Chat " .. util.count(_G.codecompanion_chats) + 1,
          description = description,
          chat = chat,
        }
      end
    end,
  })
end

---@class CodeCompanion.Chat
---@field id integer
---@field adapter CodeCompanion.Adapter
---@field current_request table
---@field bufnr integer
---@field opts CodeCompanion.ChatArgs
---@field context table
---@field saved_chat? string
---@field settings table
---@field type string
local Chat = {}

---@class CodeCompanion.ChatArgs
---@field context? table
---@field adapter? CodeCompanion.Adapter
---@field messages nil|table
---@field show_buffer nil|boolean
---@field auto_submit nil|boolean
---@field settings nil|table
---@field type nil|string
---@field saved_chat nil|string
---@field status nil|string
---@field last_role? string

---@param args CodeCompanion.ChatArgs
function Chat.new(args)
  local id = math.random(10000000)

  local self = setmetatable({
    id = id,
    context = args.context,
    saved_chat = args.saved_chat,
    opts = args,
    status = "",
    last_role = "user",
    create_buf = function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      api.nvim_buf_set_name(bufnr, string.format("[CodeCompanion] %d", id))
      api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
      api.nvim_buf_set_option(bufnr, "filetype", "codecompanion")
      api.nvim_buf_set_option(bufnr, "syntax", "markdown")
      vim.b[bufnr].codecompanion_type = "chat"

      return bufnr
    end,
  }, { __index = Chat })

  self.bufnr = self.create_buf()
  self:open()

  self.adapter = args.adapter or resolve_adapter()
  if not self.adapter then
    vim.notify("[CodeCompanion.nvim]\nNo adapter found", vim.log.levels.ERROR)
    return
  end

  self.settings = args.settings or schema.get_default(self.adapter.args.schema, args.settings)

  set_autocmds(self)
  self:render(args.messages or {})

  if args.saved_chat then
    display_tokens(self.bufnr)
  end
  if args.auto_submit then
    self:submit()
  end

  _G.codecompanion_last_chat_buffer = self
  return self
end

---Open/create the chat window
function Chat:open()
  if self:visible() then
    return
  end

  local window = config.display.chat.window
  local width = window.width > 1 and window.width or math.floor(vim.o.columns * window.width)
  local height = window.height > 1 and window.height or math.floor(vim.o.lines * window.height)

  if window.layout == "float" then
    local win_opts = {
      relative = window.relative,
      width = width,
      height = height,
      row = window.row or math.floor((vim.o.lines - height) / 2),
      col = window.col or math.floor((vim.o.columns - width) / 2),
      border = window.border,
      title = "Code Companion",
      title_pos = "center",
      zindex = 45,
    }
    self.winnr = vim.api.nvim_open_win(self.bufnr, true, win_opts)
    ui.set_win_options(self.winnr, window.opts)
  else
    self.winnr = api.nvim_get_current_win()
    api.nvim_set_current_buf(self.bufnr)
  end

  ui.buf_scroll_to_end(self.bufnr)
  keymaps.set(config.keymaps, self.bufnr, self)
end

---Render the chat buffer
---@param messages table
function Chat:render(messages)
  local lines = {}
  if config.display.chat.show_settings then
    lines = { "---" }
    local keys = schema.get_ordered_keys(self.adapter.args.schema)
    for _, key in ipairs(keys) do
      table.insert(lines, string.format("%s: %s", key, yaml.encode(self.settings[key])))
    end
    table.insert(lines, "---")
    table.insert(lines, "")
  end

  -- Start with the user heading
  if #messages == 0 then
    table.insert(lines, "# user")
    table.insert(lines, "")
    table.insert(lines, "")
  end

  -- Put the messages in the buffer
  for i, message in ipairs(messages) do
    if i > 1 then
      table.insert(lines, "")
    end
    table.insert(lines, string.format("# %s", message.role))
    table.insert(lines, "")
    for _, text in ipairs(vim.split(message.content, "\n", { plain = true, trimempty = true })) do
      table.insert(lines, text)
    end
  end

  if self.context and self.context.is_visual then
    table.insert(lines, "")
    table.insert(lines, "```" .. self.context.filetype)
    for _, line in ipairs(self.context.lines) do
      table.insert(lines, line)
    end
    table.insert(lines, "```")
  end

  local modifiable = vim.bo[self.bufnr].modifiable
  vim.bo[self.bufnr].modifiable = true
  api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
  vim.bo[self.bufnr].modified = false
  vim.bo[self.bufnr].modifiable = modifiable
end

---Submit the chat buffer's contents to the LLM
function Chat:submit()
  local bufnr = self.bufnr
  local settings, messages = parse_settings(bufnr, self.adapter), parse_messages(bufnr)
  if not messages or #messages == 0 or (not messages[#messages].content or messages[#messages].content == "") then
    return
  end

  -- Add the adapter's chat prompt
  if self.adapter.args.chat_prompt then
    table.insert(messages, {
      role = "system",
      content = self.adapter.args.chat_prompt,
    })
  end

  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = false

  -- log:trace("----- For Adapter test creation -----\nMessages: %s\n ---------- // END ----------", messages)
  -- log:trace("Settings: %s", settings)

  self.current_request = client.new():stream(self.adapter:set_params(settings), messages, function(err, data, done)
    if err then
      vim.notify("Error: " .. err, vim.log.levels.ERROR)
      return self:reset()
    end

    if done then
      self:append({ role = "user", content = "" })
      display_tokens(bufnr)
      self:reset()
      if self.status ~= "error" then
        parse_tools(self)
      end
      return api.nvim_exec_autocmds("User", { pattern = "CodeCompanionChat", data = { status = "finished" } })
    end

    if data then
      local result = self.adapter.args.callbacks.chat_output(data)

      if result and result.status == "success" then
        self:append(result.output)
      elseif result and result.status == "error" then
        self.status = "error"
        self:stop()
        vim.notify("Error: " .. result.output, vim.log.levels.ERROR)
        return self:reset()
      end
    end
  end, function()
    self.current_request = nil
  end)
end

---Stop and cancel the response from the LLM
---@return boolean
function Chat:stop()
  if self.current_request then
    local job = self.current_request
    self.current_request = nil
    job:shutdown()
    return true
  end

  return false
end

---Hide the chat buffer from view
function Chat:hide()
  local layout = config.display.chat.window.layout

  if layout == "float" then
    if self:active() then
      vim.cmd("hide")
    else
      api.nvim_win_hide(self.winnr)
    end
  else
    vim.cmd("buffer " .. vim.fn.bufnr("#"))
  end

  api.nvim_exec_autocmds(
    "User",
    { pattern = "CodeCompanionChat", data = { action = "hide_buffer", bufnr = self.bufnr } }
  )
end

---Close the current chat buffer
function Chat:close()
  if self.current_request then
    self:stop()
  end

  if _G.codecompanion_last_chat_buffer and _G.codecompanion_last_chat_buffer.bufnr == self.bufnr then
    _G.codecompanion_last_chat_buffer = nil
  end

  _G.codecompanion_chats[self.bufnr] = nil
  api.nvim_buf_delete(self.bufnr, { force = true })
end

---Get the last line and column in the chat buffer
---@return integer, integer, integer
function Chat:last()
  local line_count = api.nvim_buf_line_count(self.bufnr)

  local last_line = line_count - 1
  if last_line < 0 then
    return 0, 0, line_count
  end

  local last_line_content = api.nvim_buf_get_lines(self.bufnr, -2, -1, false)
  if not last_line_content or #last_line_content == 0 then
    return last_line, 0, line_count
  end

  local last_column = #last_line_content[1]

  return last_line, last_column, line_count
end

---Append a message to the chat buffer
---@param data table
---@param opts? table
function Chat:append(data, opts)
  local lines = {}

  if (data.role and data.role ~= self.last_role) or (opts and opts.force_role) then
    self.last_role = data.role
    table.insert(lines, "")
    table.insert(lines, "")
    table.insert(lines, string.format("# %s", data.role))
    table.insert(lines, "")
  end

  if data.content then
    for _, text in ipairs(vim.split(data.content, "\n", { plain = true, trimempty = false })) do
      table.insert(lines, text)
    end

    local modifiable = vim.bo[self.bufnr].modifiable
    vim.bo[self.bufnr].modifiable = true

    local last_line, last_column, line_count = self:last()
    if opts and opts.insert_at then
      last_line = opts.insert_at
      last_column = 0
    end

    local cursor_moved = api.nvim_win_get_cursor(0)[1] == line_count

    api.nvim_buf_set_text(self.bufnr, last_line, last_column, last_line, last_column, lines)

    vim.bo[self.bufnr].modified = false
    vim.bo[self.bufnr].modifiable = modifiable

    if cursor_moved and self:active() then
      ui.buf_scroll_to_end(self.bufnr)
    elseif not self:active() then
      ui.buf_scroll_to_end(self.bufnr)
    end
  end
end

---Wrapper for appending a message to the chat buffer
---@param data table
---@param opts? table
function Chat:add_message(data, opts)
  self:append({ role = data.role, content = data.content }, opts)

  if opts and opts.notify then
    vim.api.nvim_echo({
      { "[CodeCompanion.nvim]\n", "Normal" },
      { opts.notify, "MoreMsg" },
    }, true, {})
  end
end

---When a request has finished, reset the chat buffer
function Chat:reset()
  local bufnr = self.bufnr

  self.status = ""
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = true
end

---Get the messages from the chat buffer
---@return table, table
function Chat:get_messages()
  return parse_settings(self.bufnr, self.adapter), parse_messages(self.bufnr)
end

---Determine if the chat buffer is visible
---@return boolean
function Chat:visible()
  return self.winnr and vim.api.nvim_win_is_valid(self.winnr) and vim.api.nvim_win_get_buf(self.winnr) == self.bufnr
end

---Determine if the current chat buffer is active
---@return boolean
function Chat:active()
  return api.nvim_get_current_buf() == self.bufnr
end

return Chat
