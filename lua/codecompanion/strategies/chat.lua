local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")
local schema = require("codecompanion.schema")
local yaml = require("codecompanion.utils.yaml")

local ui = require("codecompanion.strategies.chat.ui")

local hash = require("codecompanion.utils.hash")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils.util")

local api = vim.api

local CONSTANTS = {
  AUTOCMD_GROUP = "codecompanion.chat",

  STATUS_ERROR = "error",
  STATUS_SUCCESS = "success",

  BLANK_DESC = "[No messages]",
}

local llm_role = config.strategies.chat.roles.llm
local user_role = config.strategies.chat.roles.user

---Make an id from a string or table
---@param val string|table
---@return number
local function make_id(val)
  return hash.hash(val)
end

local _cached_settings = {}

---Parse the chat buffer for settings
---@param bufnr integer
---@param adapter? CodeCompanion.Adapter
---@param ts_query? string
---@return table
local function buf_parse_settings(bufnr, adapter, ts_query)
  if _cached_settings[bufnr] then
    return _cached_settings[bufnr]
  end

  -- If the user has disabled settings in the chat buffer, use the default settings
  if not config.display.chat.show_settings then
    if adapter then
      _cached_settings[bufnr] = adapter:get_default_settings()

      return _cached_settings[bufnr]
    end
  end

  local settings = {}
  local parser = vim.treesitter.get_parser(bufnr, "yaml", { ignore_injections = false })
  local query = vim.treesitter.query.get("yaml", "chat")
  local root = parser:parse()[1]:root()

  for _, match in query:iter_matches(root, bufnr, nil, nil, { all = false }) do
    local value = vim.treesitter.get_node_text(match[1], bufnr)

    settings = yaml.decode(value)
    break
  end

  if not settings then
    log:error("Failed to parse settings in chat buffer")
    return {}
  end

  return settings
end

---Parse the chat buffer for the last message
---@param bufnr integer
---@return table{content: string}
local function buf_parse_message(bufnr)
  local parser = vim.treesitter.get_parser(bufnr, "markdown")
  local query = vim.treesitter.query.get("markdown", "chat")

  local tree = parser:parse()[1]
  local root = tree:root()

  local last_section = nil
  local contents = {}

  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    if query.captures[id] == "content" then
      last_section = node
      contents = {}
    elseif query.captures[id] == "text" and last_section then
      table.insert(contents, vim.treesitter.get_node_text(node, bufnr))
    end
  end

  if #contents > 0 then
    return { content = vim.trim(table.concat(contents, "\n\n")) }
  end

  return {}
end

---@class CodeCompanion.Chat
---@return nil
local function buf_parse_tools(chat)
  local assistant_parser = vim.treesitter.get_parser(chat.bufnr, "markdown")
  local assistant_query = vim.treesitter.query.parse(
    "markdown",
    string.format(
      [[
(
  (section
    (atx_heading) @heading
    (#match? @heading "## %s")
  ) @content
)
  ]],
      llm_role
    )
  )
  local assistant_tree = assistant_parser:parse()[1]

  local llm = {}
  for id, node in assistant_query:iter_captures(assistant_tree:root(), chat.bufnr, 0, -1) do
    local name = assistant_query.captures[id]
    if name == "content" then
      local response = vim.treesitter.get_node_text(node, chat.bufnr)
      table.insert(llm, response)
    end
  end

  -- Only work with the last response from the LLM
  local response = llm[#llm]

  local parser = vim.treesitter.get_string_parser(response, "markdown")
  local tree = parser:parse()[1]
  local query = vim.treesitter.query.parse(
    "markdown",
    [[(
 (section
  (fenced_code_block
    (info_string) @lang
    (code_fence_content) @tool
  ) (#match? @lang "xml"))
)
]]
  )

  local tools = {}
  for id, node in query:iter_captures(tree:root(), response, 0, -1) do
    local name = query.captures[id]
    if name == "tool" then
      local tool = vim.treesitter.get_node_text(node, response)
      table.insert(tools, tool)
    end
  end

  log:debug("Tool detected: %s", tools)

  if not vim.tbl_isempty(tools) then
    vim.iter(tools):each(function(t)
      return chat.tools:setup(chat, t)
    end)
  end
end

---Parse the chat buffer for a code block
---returns the code block that the cursor is in or the last code block
---@param bufnr integer
---@param cursor? table
---@return TSNode | nil
local function buf_find_codeblock(bufnr, cursor)
  local parser = vim.treesitter.get_parser(bufnr, "markdown")
  local root = parser:parse()[1]:root()
  local query = vim.treesitter.query.get("markdown", "chat")
  if query == nil then
    return nil
  end

  local last_match = nil
  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    if query.captures[id] == "code" then
      if cursor then
        local start_row, start_col, end_row, end_col = node:range()
        if cursor[1] >= start_row and cursor[1] <= end_row and cursor[2] >= start_col and cursor[2] <= end_col then
          return node
        end
      end
      last_match = node
    end
  end

  return last_match
end

---Methods that are available outside of CodeCompanion
---@type table<CodeCompanion.Chat>
local chatmap = {}

---@type table
_G.codecompanion_buffers = {}

---Used to record the last chat buffer that was opened
---@type CodeCompanion.Chat|nil
---@diagnostic disable-next-line: missing-fields
local last_chat = {}

---@class CodeCompanion.Chat
local Chat = {}

---@param args CodeCompanion.ChatArgs
function Chat.new(args)
  local id = math.random(10000000)
  log:trace("Chat created with ID %d", id)

  local self = setmetatable({
    opts = args,
    context = args.context,
    cycle = 0,
    id = id,
    last_role = args.last_role or config.constants.USER_ROLE,
    messages = args.messages or {},
    refs = {},
    status = "",
    subscribers = {},
    tools_in_use = {},
    create_buf = function()
      local bufnr = api.nvim_create_buf(false, true)
      api.nvim_buf_set_name(bufnr, string.format("[CodeCompanion] %d", id))
      vim.bo[bufnr].filetype = "codecompanion"

      return bufnr
    end,
  }, { __index = Chat })

  self.bufnr = self.create_buf()
  self.aug = api.nvim_create_augroup(CONSTANTS.AUTOCMD_GROUP .. ":" .. self.bufnr, {
    clear = false,
  })
  self.References = require("codecompanion.strategies.chat.references").new(self)
  self.tools = require("codecompanion.strategies.chat.tools").new({ bufnr = self.bufnr, messages = self.messages })
  self.variables = require("codecompanion.strategies.chat.variables").new()

  table.insert(_G.codecompanion_buffers, self.bufnr)
  chatmap[self.bufnr] = {
    name = "Chat " .. vim.tbl_count(chatmap) + 1,
    description = CONSTANTS.BLANK_DESC,
    strategy = "chat",
    chat = self,
  }

  self.adapter = adapters.resolve(self.opts.adapter)
  if not self.adapter then
    return log:error("No adapter found")
  end
  util.fire("ChatAdapter", {
    bufnr = self.bufnr,
    adapter = adapters.make_safe(self.adapter),
  })
  util.fire("ChatModel", { bufnr = self.bufnr, model = self.adapter.schema.model.default })

  self:apply_settings(self.opts.settings)

  ui = ui.new({
    adapter = self.adapter,
    id = self.id,
    bufnr = self.bufnr,
    roles = { user = user_role, llm = llm_role },
    settings = self.settings,
  })

  self.close_last_chat()
  ui:open():render(self.context, self.messages, self.opts):set_extmarks(self.opts)

  if config.strategies.chat.keymaps then
    keymaps.set(config.strategies.chat.keymaps, self.bufnr, self)
  end

  self:set_system_prompt():set_autocmds()

  last_chat = self

  if self.opts.auto_submit then
    self:submit()
  end

  return self
end

---Set the autocmds for the chat buffer
---@return nil
function Chat:set_autocmds()
  local bufnr = self.bufnr
  api.nvim_create_autocmd("BufEnter", {
    group = self.aug,
    buffer = bufnr,
    desc = "Log the most recent chat buffer",
    callback = function()
      last_chat = self
    end,
  })

  if config.display.chat.show_settings then
    api.nvim_create_autocmd("CursorMoved", {
      group = self.aug,
      buffer = bufnr,
      desc = "Show settings information in the CodeCompanion chat buffer",
      callback = function()
        local key_name, node = self:_get_settings_key()
        if not key_name or not node then
          vim.diagnostic.set(config.INFO_NS, self.bufnr, {})
          return
        end

        local key_schema = self.adapter.schema[key_name]
        if key_schema and key_schema.desc then
          local lnum, col, end_lnum, end_col = node:range()
          local diagnostic = {
            lnum = lnum,
            col = col,
            end_lnum = end_lnum,
            end_col = end_col,
            severity = vim.diagnostic.severity.INFO,
            message = key_schema.desc,
          }
          vim.diagnostic.set(config.INFO_NS, self.bufnr, { diagnostic })
        end
      end,
    })

    -- Validate the settings
    api.nvim_create_autocmd("InsertLeave", {
      group = self.aug,
      buffer = bufnr,
      desc = "Parse the settings in the CodeCompanion chat buffer for any errors",
      callback = function()
        local settings = buf_parse_settings(bufnr, self.adapter, [[((stream (_)) @block)]])

        local errors = schema.validate(self.adapter.schema, settings, self.adapter)
        local node = settings.__ts_node

        local items = {}
        if errors and node then
          for child in node:iter_children() do
            assert(child:type() == "block_mapping_pair")
            local key = vim.treesitter.get_node_text(child:named_child(0), self.bufnr)
            if errors[key] then
              local lnum, col, end_lnum, end_col = child:range()
              table.insert(items, {
                lnum = lnum,
                col = col,
                end_lnum = end_lnum,
                end_col = end_col,
                severity = vim.diagnostic.severity.ERROR,
                message = errors[key],
              })
            end
          end
        end
        vim.diagnostic.set(config.ERROR_NS, self.bufnr, items)
      end,
    })
  end
end

---Get the settings key at the current cursor position
---@param opts? table
function Chat:_get_settings_key(opts)
  opts = vim.tbl_extend("force", opts or {}, {
    lang = "yaml",
    ignore_injections = false,
  })
  local node = vim.treesitter.get_node(opts)
  while node and node:type() ~= "block_mapping_pair" do
    node = node:parent()
  end
  if not node then
    return
  end
  local key_node = node:named_child(0)
  local key_name = vim.treesitter.get_node_text(key_node, self.bufnr)
  return key_name, node
end

---Apply custom settings to the chat buffer
---@param settings table
---@return self
function Chat:apply_settings(settings)
  -- Clear the cache
  _cached_settings = {}

  self.settings = settings or schema.get_default(self.adapter.schema, self.opts.settings)

  return self
end

---Set a model in the chat buffer
---@param model string
---@return self
function Chat:apply_model(model)
  if _cached_settings[self.bufnr] then
    _cached_settings[self.bufnr].model = model
  end

  self.adapter.schema.model.default = model

  return self
end

---CodeCompanion models completion source
---@param request table
---@param callback fun(request: table)
---@return nil
function Chat:complete_models(request, callback)
  local items = {}
  local cursor = api.nvim_win_get_cursor(0)
  local key_name, node = self:_get_settings_key({ pos = { cursor[1] - 1, 1 } })
  if not key_name or not node then
    callback({ items = items, isIncomplete = false })
    return
  end

  local key_schema = self.adapter.schema[key_name]
  if key_schema.type == "enum" then
    local choices = key_schema.choices
    if type(choices) == "function" then
      choices = choices(self.adapter)
    end
    for _, choice in ipairs(choices) do
      table.insert(items, {
        label = choice,
        kind = require("cmp").lsp.CompletionItemKind.Keyword,
      })
    end
  end

  callback({ items = items, isIncomplete = false })
end

---Set the system prompt in the chat buffer
---@return CodeCompanion.Chat
function Chat:set_system_prompt()
  local prompt = config.opts.system_prompt
  if prompt ~= "" then
    if type(prompt) == "function" then
      prompt = prompt({
        adapter = self.adapter,
        language = config.opts.language,
      })
    end

    local system_prompt = {
      role = config.constants.SYSTEM_ROLE,
      content = prompt,
    }
    system_prompt.id = make_id(system_prompt)
    system_prompt.opts = { visible = false }
    table.insert(self.messages, 1, system_prompt)
  end
  return self
end

---Toggle the system prompt in the chat buffer
---@return nil
function Chat:toggle_system_prompt()
  if self.messages[1] and self.messages[1].role == config.constants.SYSTEM_ROLE then
    util.notify("Removed system prompt")
    table.remove(self.messages, 1)
  else
    util.notify("Added system prompt")
    self:set_system_prompt()
  end
end

---Parse the last message for any variables
---@param message table
---@return CodeCompanion.Chat
function Chat:parse_msg_for_vars(message)
  local vars = self.variables:parse(self, message)

  if vars then
    message.content = self.variables:replace(message.content)
    message.id = make_id({ role = message.role, content = message.content })
    self:add_message(
      { role = config.constants.USER_ROLE, content = message.content },
      { visible = false, tag = "variable" }
    )
  end

  return self
end

---Determine if the chat buffer has any tools in use
---@return boolean
function Chat:has_tools()
  return not vim.tbl_isempty(self.tools_in_use)
end

---Add the given tool to the chat buffer
---@param tool string The name of the tool
---@param tool_config table The tool from the config
---@return CodeCompanion.Chat
function Chat:add_tool(tool, tool_config)
  if self.tools_in_use[tool] then
    return self
  end

  -- Add the overarching agent system prompt first
  if not self:has_tools() then
    local id = string.upper(tool) .. " tool"

    self:add_message({
      role = config.constants.SYSTEM_ROLE,
      content = config.strategies.agent.tools.opts.system_prompt,
    }, { visible = false, reference = id, tag = "tool" })

    self.References:add({
      source = "tool",
      name = "tool",
      id = id,
    })
  end

  self.tools_in_use[tool] = true

  local resolved = self.tools.resolve(tool_config)
  if resolved then
    self:add_message(
      { role = config.constants.SYSTEM_ROLE, content = resolved.system_prompt(resolved.schema) },
      { visible = false, tag = "tool" }
    )
  end

  util.fire("ChatToolAdded", { bufnr = self.bufnr, tool = tool })

  return self
end

---Add a message to the message table
---@param data table {role: string, content: string}
---@param opts? table Options for the message
---@return CodeCompanion.Chat
function Chat:add_message(data, opts)
  opts = opts or { visible = true }
  if opts.visible == nil then
    opts.visible = true
  end

  local message = {
    role = data.role,
    content = data.content,
  }
  message.id = make_id(message)
  message.opts = opts
  if opts.index then
    table.insert(self.messages, opts.index, message)
  else
    table.insert(self.messages, message)
  end

  return self
end

---Apply any tools or variables that a user has tagged in their message
---@param message table
---@return nil
function Chat:apply_tools_and_variables(message)
  if self.tools:parse(self, message) then
    message.content = self.tools:replace(message.content)
  end
  if self.variables:parse(self, message) then
    message.content = self.variables:replace(message.content)
  end
end

---Are there any user messages in the chat buffer?
---@param message table
---@return boolean
function Chat:has_user_messages(message)
  if vim.tbl_isempty(message) then
    local has_user_messages = vim
      .iter(self.messages)
      :filter(function(msg)
        return msg.role == config.constants.USER_ROLE
      end)
      :totable()

    if #has_user_messages == 0 then
      return false
    end
  end
  return true
end

---Submit the chat buffer's contents to the LLM
---@param opts? table
---@return nil
function Chat:submit(opts)
  opts = opts or {}

  local bufnr = self.bufnr

  local message = buf_parse_message(bufnr)
  if not self:has_user_messages(message) then
    return log:warn("No messages to submit")
  end

  --- Only send the user's last message if we're not regenerating the response
  if not opts.regenerate and not vim.tbl_isempty(message) then
    self:add_message({ role = config.constants.USER_ROLE, content = message.content })
  end
  message = self.References:clear(self.messages[#self.messages])

  self:apply_tools_and_variables(message)

  -- Check if the user has manually overriden the adapter. This is useful if the
  -- user loses their internet connection and wants to switch to a local LLM
  if vim.g.codecompanion_adapter and self.adapter.name ~= vim.g.codecompanion_adapter then
    self.adapter = adapters.resolve(config.adapters[vim.g.codecompanion_adapter])
  end

  local settings = buf_parse_settings(bufnr, self.adapter)
  settings = self.adapter:map_schema_to_params(settings)

  log:debug("Settings:\n%s", settings)
  log:debug("Messages:\n%s", self.messages)
  log:info("Chat request started")

  ui:lock_buf()
  self.cycle = self.cycle + 1
  self.current_request = client
    .new({ adapter = settings })
    :request(self.adapter:map_roles(vim.deepcopy(self.messages)), {
      ---@param err string
      ---@param data table
      callback = function(err, data)
        if err then
          self.status = CONSTANTS.STATUS_ERROR
          return self:done()
        end

        if data then
          ui:get_tokens(data)

          local result = self.adapter.handlers.chat_output(self.adapter, data)
          if result and result.status == CONSTANTS.STATUS_SUCCESS then
            if result.output.role then
              result.output.role = config.constants.LLM_ROLE
            end
            self.status = CONSTANTS.STATUS_SUCCESS
            self:add_buf_message(result.output)
          end
        end
      end,
      done = function()
        self:done()
      end,
    }, { bufnr = bufnr })
end

---After the response from the LLM is received...
---@return nil
function Chat:done()
  self.current_request = nil
  self:add_message({ role = config.constants.LLM_ROLE, content = buf_parse_message(self.bufnr).content })

  self:add_buf_message({ role = config.constants.USER_ROLE, content = "" })
  self.References:render()
  ui:display_tokens()

  if self.status == CONSTANTS.STATUS_SUCCESS and self:has_tools() then
    buf_parse_tools(self)
  end

  log:info("Chat request completed")
  self:reset()

  if self.has_subscribers then
    local function action_subscription(subscriber)
      subscriber.callback(self)
      if subscriber.type == "once" then
        self:unsubscribe(subscriber.id)
      end
    end

    vim.iter(self.subscribers):each(function(subscriber)
      if subscriber.order and subscriber.order <= self.cycle then
        action_subscription(subscriber)
      elseif not subscriber.order then
        action_subscription(subscriber)
      end
    end)
  end
end

---Regenerate the response from the LLM
---@return nil
function Chat:regenerate()
  if self.messages[#self.messages].role == config.constants.LLM_ROLE then
    table.remove(self.messages, #self.messages)
    self:add_buf_message({ role = config.constants.USER_ROLE, content = "_Regenerating response..._" })
    self:submit({ regenerate = true })
  end
end

---Stop streaming the response from the LLM
---@return nil
function Chat:stop()
  local job
  if self.current_tool then
    job = self.current_tool
    self.current_tool = nil

    _G.codecompanion_cancel_tool = true
    job:shutdown()
  end
  if self.current_request then
    job = self.current_request
    self.current_request = nil
    if job then
      job:shutdown()
    end
  end
end

---Close the current chat buffer
---@return nil
function Chat:close()
  if self.current_request then
    self:stop()
  end

  if last_chat and last_chat.bufnr == self.bufnr then
    last_chat = nil
  end

  table.remove(
    _G.codecompanion_buffers,
    vim.iter(_G.codecompanion_buffers):enumerate():find(function(_, v)
      return v == self.bufnr
    end)
  )
  chatmap[self.bufnr] = nil
  api.nvim_buf_delete(self.bufnr, { force = true })
  api.nvim_clear_autocmds({ group = self.aug })
  api.nvim_clear_autocmds({ group = ui.aug })
  util.fire("ChatClosed", { bufnr = self.bufnr })
  util.fire("ChatAdapter", { bufnr = self.bufnr, adapter = nil })
  util.fire("ChatModel", { bufnr = self.bufnr, model = nil })
  self = nil
end

---Add a message directly to the chat buffer. This will be visible to the user
---@param data table
---@param opts? table
function Chat:add_buf_message(data, opts)
  local lines = {}
  local bufnr = self.bufnr
  local new_response = false

  if (data.role and data.role ~= self.last_role) or (opts and opts.force_role) then
    new_response = true
    self.last_role = data.role
    table.insert(lines, "")
    table.insert(lines, "")
    ui:format_header(lines, config.strategies.chat.roles[data.role])
  end

  if data.content then
    for _, text in ipairs(vim.split(data.content, "\n", { plain = true, trimempty = false })) do
      table.insert(lines, text)
    end

    ui:unlock_buf()

    local last_line, last_column, line_count = ui:last()
    if opts and opts.insert_at then
      last_line = opts.insert_at
      last_column = 0
    end

    local cursor_moved = api.nvim_win_get_cursor(0)[1] == line_count
    api.nvim_buf_set_text(bufnr, last_line, last_column, last_line, last_column, lines)

    if new_response then
      ui:render_headers()
    end

    if self.last_role ~= config.constants.USER_ROLE then
      ui:lock_buf()
    end

    if cursor_moved and ui:is_active() then
      ui:follow()
    elseif not ui:is_active() then
      ui:follow()
    end
  end
end

---When a request has finished, reset the chat buffer
---@return nil
function Chat:reset()
  self.status = ""
  ui:unlock_buf()
end

---Get the messages from the chat buffer
---@return table
function Chat:get_messages()
  return self.messages
end

---Subscribe to a chat buffer
---@param event table {name: string, type: string, callback: fun}
function Chat:subscribe(event)
  table.insert(self.subscribers, event)
end

---Does the chat buffer have any subscribers?
function Chat:has_subscribers()
  return #self.subscribers > 0
end

---Unsubscribe an object from a chat buffer
---@param id integer|string
function Chat:unsubscribe(id)
  for i, subscriber in ipairs(self.subscribers) do
    if subscriber.id == id then
      table.remove(self.subscribers, i)
    end
  end
end

---Fold code under the user's heading in the chat buffer
---@return CodeCompanion.Chat.UI
function Chat:fold_code()
  return ui:fold_code()
end

---Get currently focused code block or the last one in the chat buffer
---@return TSNode | nil
function Chat:get_codeblock()
  local cursor = api.nvim_win_get_cursor(0)
  return buf_find_codeblock(self.bufnr, cursor)
end

---Clear the chat buffer
---@return nil
function Chat:clear()
  self.refs = {}
  self.messages = {}
  self.tools_in_use = {}

  log:trace("Clearing chat buffer")
  ui:render(self.context, self.messages, self.opts):set_extmarks(self.opts)
  self:set_system_prompt()
end

---Display the chat buffer's settings and messages
function Chat:debug()
  if vim.tbl_isempty(self.messages) then
    return
  end

  return buf_parse_settings(self.bufnr, self.adapter), self.messages
end

---Returns the chat object(s) based on the buffer number
---@param bufnr? integer
---@return CodeCompanion.Chat|table
function Chat.buf_get_chat(bufnr)
  if not bufnr then
    return vim
      .iter(pairs(chatmap))
      :map(function(_, v)
        return v
      end)
      :totable()
  end

  if bufnr == 0 then
    bufnr = api.nvim_get_current_buf()
  end
  return chatmap[bufnr].chat
end

---Returns the last chat that was visible
---@return CodeCompanion.Chat|nil
function Chat.last_chat()
  if not last_chat or vim.tbl_isempty(last_chat) then
    return nil
  end
  return last_chat
end

---Close the last chat buffer
---@return nil
function Chat.close_last_chat()
  if last_chat and not vim.tbl_isempty(last_chat) then
    local last_ui = require("codecompanion.strategies.chat.ui").new({
      bufnr = last_chat.bufnr,
    })
    if last_ui:is_visible() then
      last_ui:hide()
    end
  end
end

return Chat
