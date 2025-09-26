--=============================================================================
-- The Chat Buffer - Where all of the logic for conversing with an LLM sits
--=============================================================================

---@class CodeCompanion.Chat
---@field acp_connection? CodeCompanion.ACP.Connection The ACP session ID and connection
---@field adapter CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter The adapter to use for the chat
---@field builder CodeCompanion.Chat.UI.Builder The builder for the chat UI
---@field create_buf fun(): number The function that creates a new buffer for the chat
---@field aug number The ID for the autocmd group
---@field bufnr number The buffer number of the chat
---@field buffer_context table The context of the buffer that the chat was initiated from
---@field callbacks table<string, fun(chat: CodeCompanion.Chat)[]> A table of callback functions that are executed at various points
---@field chat_parser vim.treesitter.LanguageTree The Markdown Tree-sitter parser for the chat buffer
---@field current_request table|nil The current request being executed
---@field current_tool table The current tool being executed
---@field cycle number Records the number of turn-based interactions (User -> LLM) that have taken place
---@field edit_tracker? CodeCompanion.Chat.EditTracker Edit tracking information for the chat
---@field from_prompt_library? boolean Whether the chat was initiated from the prompt library
---@field header_line number The line number of the user header that any Tree-sitter parsing should start from
---@field header_ns number The namespace for the virtual text that appears in the header
---@field id number The unique identifier for the chat
---@field messages? CodeCompanion.Chat.Messages The messages in the chat buffer
---@field opts CodeCompanion.ChatArgs Store all arguments in this table
---@field context CodeCompanion.Chat.Context
---@field context_items? table<CodeCompanion.Chat.Context> Context which is sent to the LLM e.g. buffers, slash command output
---@field settings? table The settings that are used in the adapter of the chat buffer
---@field subscribers table The subscribers to the chat buffer
---@field tokens? nil|number The number of tokens in the chat
---@field tools CodeCompanion.Tools The tools coordinator that executes available tools
---@field tool_registry CodeCompanion.Chat.ToolRegistry Methods for handling interactions between the chat buffer and tools
---@field ui CodeCompanion.Chat.UI The UI of the chat buffer
---@field variables? CodeCompanion.Variables The variables available to the user
---@field watched_buffers CodeCompanion.Watchers The buffer watcher instance
---@field window_opts? table Window configuration options for the chat buffer
---@field intro_message? string The welcome message that is displayed in the chat buffer
---@field yaml_parser vim.treesitter.LanguageTree The Yaml Tree-sitter parser for the chat buffer
---@field _last_role string The last role that was rendered in the chat buffer
---@field _tool_monitors? table A table of tool monitors that are currently running in the chat buffer

---@class CodeCompanion.ChatArgs Arguments that can be injected into the chat
---@field acp_session_id? string The ACP session ID which links to this chat buffer
---@field adapter? CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter The adapter used in this chat buffer
---@field auto_submit? boolean Automatically submit the chat when the chat buffer is created
---@field buffer_context? table Context of the buffer that the chat was initiated from
---@field callbacks table<string, fun(chat: CodeCompanion.Chat)[]> A table of callback functions that are executed at various points
---@field from_prompt_library? boolean Whether the chat was initiated from the prompt library
---@field ignore_system_prompt? boolean Do not send the default system prompt with the request
---@field last_role string The last role that was rendered in the chat buffer-
---@field messages? CodeCompanion.Chat.Messages The messages to display in the chat buffer
---@field settings? table The settings that are used in the adapter of the chat buffer
---@field status? string The status of any running jobs in the chat buffe
---@field stop_context_insertion? boolean Stop any visual selection from being automatically inserted into the chat buffer
---@field tokens? table Total tokens spent in the chat buffer so far
---@field intro_message? string The welcome message that is displayed in the chat buffer
---@field window_opts? table Window configuration options for the chat buffer

local adapters = require("codecompanion.adapters")
local completion = require("codecompanion.providers.completion")
local config = require("codecompanion.config")
local edit_tracker = require("codecompanion.strategies.chat.edit_tracker")
local hash = require("codecompanion.utils.hash")
local helpers = require("codecompanion.strategies.chat.helpers")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local parser = require("codecompanion.strategies.chat.parser")
local schema = require("codecompanion.schema")
local util = require("codecompanion.utils")

local api = vim.api
local fmt = string.format

local CONSTANTS = {
  AUTOCMD_GROUP = "codecompanion.chat",

  STATUS_CANCELLING = "cancelling",
  STATUS_ERROR = "error",
  STATUS_SUCCESS = "success",

  BLANK_DESC = "[No messages]",
}

local clients = {} -- Cache for HTTP and ACP clients
local llm_role = config.strategies.chat.roles.llm
local user_role = config.strategies.chat.roles.user
local show_settings = config.display.chat.show_settings

--=============================================================================
-- Private methods
--=============================================================================

---Add updated content from the pins to the chat buffer
---@param chat CodeCompanion.Chat
---@return nil
local function add_pins(chat)
  local pins = vim
    .iter(chat.context_items)
    :filter(function(ctx)
      return ctx.opts.pinned
    end)
    :totable()

  if vim.tbl_isempty(pins) then
    return
  end

  for _, pin in ipairs(pins) do
    -- Don't add the pin twice in the same cycle
    local exists = false
    vim.iter(chat.messages):each(function(msg)
      if msg.opts and msg.opts.context_id == pin.id and msg.cycle == chat.cycle then
        exists = true
      end
    end)
    if not exists then
      util.fire("ChatPin", { bufnr = chat.bufnr, id = chat.id, pin_id = pin.id })
      require(pin.source)
        .new({ Chat = chat })
        :output({ path = pin.path, bufnr = pin.bufnr, params = pin.params }, { pin = true })
    end
  end
end

---Get the appropriate client for the adapter type
---@param adapter CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter
---@return table
local function get_client(adapter)
  if adapter.type == "acp" then
    if not clients.acp then
      clients.acp = require("codecompanion.acp")
    end
    return clients.acp
  else
    if not clients.http then
      clients.http = require("codecompanion.http")
    end
    return clients.http
  end
end

---Find a message in the table that has a specific tool call ID
---@param id string
---@param messages CodeCompanion.Chat.Messages
---@return table|nil
local function find_tool_call(id, messages)
  for _, msg in ipairs(messages) do
    if msg.tool_call_id and msg.tool_call_id == id then
      return msg
    end
  end
  return nil
end

---Increment the cycle count in the chat buffer
---@param chat CodeCompanion.Chat
---@return nil
local function increment_cycle(chat)
  chat.cycle = chat.cycle + 1
end

---Make an id from a string or table
---@param val string|table
---@return number
local function make_id(val)
  return hash.hash(val)
end

---Set the editable text area. This allows us to scope the Tree-sitter queries to a specific area
---@param chat CodeCompanion.Chat
---@param modifier? number
---@return nil
local function set_text_editing_area(chat, modifier)
  modifier = modifier or 0
  chat.header_line = api.nvim_buf_line_count(chat.bufnr) + modifier
end

---Ready the chat buffer for the next round of conversation
---@param chat CodeCompanion.Chat
---@param opts? table
---@return nil
local function ready_chat_buffer(chat, opts)
  opts = opts or {}

  if not opts.auto_submit and chat._last_role ~= config.constants.USER_ROLE then
    increment_cycle(chat)
    chat:add_buf_message({ role = config.constants.USER_ROLE, content = "" })

    set_text_editing_area(chat, -2)
    chat.ui:display_tokens(chat.chat_parser, chat.header_line)
    chat.context:render()

    chat:dispatch("on_ready")
  end

  chat:update_metadata()

  -- If we're automatically responding to a tool output, we need to leave some
  -- space for the LLM's response so we can then display the user prompt again
  if opts.auto_submit then
    chat.ui:add_line_break()
    chat.ui:add_line_break()
  end

  log:info("Chat request finished")
  chat:reset()
end

---Used to record the last chat buffer that was opened
---@type CodeCompanion.Chat|nil
---@diagnostic disable-next-line: missing-fields
local last_chat = {}

---Set the autocmds for the chat buffer
---@param chat CodeCompanion.Chat
---@return nil
local function set_autocmds(chat)
  local bufnr = chat.bufnr
  api.nvim_create_autocmd("BufEnter", {
    group = chat.aug,
    buffer = bufnr,
    desc = "Log the most recent chat buffer",
    callback = function()
      last_chat = chat
    end,
  })

  api.nvim_create_autocmd("CompleteDone", {
    group = chat.aug,
    buffer = bufnr,
    callback = function()
      local item = vim.v.completed_item
      if item.user_data and item.user_data.type == "slash_command" then
        -- Clear the word from the buffer
        local row, col = unpack(api.nvim_win_get_cursor(0))
        api.nvim_buf_set_text(bufnr, row - 1, col - #item.word, row - 1, col, { "" })

        completion.slash_commands_execute(item.user_data, chat)
      end
    end,
  })

  if show_settings then
    api.nvim_create_autocmd("CursorMoved", {
      group = chat.aug,
      buffer = bufnr,
      desc = "Show settings information in the CodeCompanion chat buffer",
      callback = function()
        if chat.adapter.type ~= "http" then
          return
        end

        local key_name, node = parser.get_settings_key(chat)
        if not key_name or not node then
          vim.diagnostic.set(config.INFO_NS, chat.bufnr, {})
          return
        end

        local key_schema = chat.adapter.schema[key_name]
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
          vim.diagnostic.set(config.INFO_NS, chat.bufnr, { diagnostic })
        end
      end,
    })

    -- Validate the settings
    api.nvim_create_autocmd("InsertLeave", {
      group = chat.aug,
      buffer = bufnr,
      desc = "Parse the settings in the CodeCompanion chat buffer for any errors",
      callback = function()
        if chat.adapter.type ~= "http" then
          return
        end

        local adapter = chat.adapter
        ---@cast adapter CodeCompanion.HTTPAdapter

        local settings = parser.settings(bufnr, chat.yaml_parser, adapter)

        local errors = schema.validate(adapter.schema, settings, adapter)
        local node = settings.__ts_node

        local items = {}
        if errors and node then
          for child in node:iter_children() do
            assert(child:type() == "block_mapping_pair")
            local key = vim.treesitter.get_node_text(child:named_child(0), chat.bufnr)
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
        vim.diagnostic.set(config.ERROR_NS, chat.bufnr, items)
      end,
    })
  end
end

--=============================================================================
-- Public methods
--=============================================================================

---Methods that are available outside of CodeCompanion
---@type table<CodeCompanion.Chat>
local chatmap = {}

---@type table
_G.codecompanion_buffers = {}

---@type table
_G.codecompanion_chat_metadata = {}

---@class CodeCompanion.Chat
local Chat = {}

Chat.MESSAGE_TYPES = {
  LLM_MESSAGE = "llm_message",
  REASONING_MESSAGE = "reasoning_message",
  SYSTEM_MESSAGE = "system_message",
  TOOL_MESSAGE = "tool_message",
  USER_MESSAGE = "user_message",
}

---@param args CodeCompanion.ChatArgs
---@return CodeCompanion.Chat
function Chat.new(args)
  local id = math.random(10000000)
  log:trace("Chat created with ID %d", id)

  local self = setmetatable({
    acp_session_id = args.acp_session_id or nil,
    buffer_context = args.buffer_context,
    callbacks = {},
    context_items = {},
    cycle = 1,
    header_line = 1,
    from_prompt_library = args.from_prompt_library or false,
    id = id,
    messages = args.messages or {},
    opts = args,
    status = "",
    intro_message = args.intro_message or config.display.chat.intro_message,
    create_buf = function()
      local bufnr = api.nvim_create_buf(false, true)
      api.nvim_buf_set_name(bufnr, fmt("[CodeCompanion] %d", id))
      api.nvim_buf_set_option(bufnr, "filetype", "codecompanion")
      api.nvim_buf_set_option(bufnr, "undolevels", config.strategies.chat.opts.undolevels or 10)

      -- Safely attach treesitter
      vim.schedule(function()
        pcall(vim.treesitter.start, bufnr)
      end)

      -- Set up omnifunc for automatic completion when no other completion provider is active
      local completion_provider = config.strategies.chat.opts.completion_provider
      if completion_provider == "default" then
        vim.bo[bufnr].omnifunc = "v:lua.require'codecompanion.providers.completion.default.omnifunc'.omnifunc"
      end

      return bufnr
    end,
    _last_role = args.last_role or config.constants.USER_ROLE,
  }, { __index = Chat })
  ---@cast self CodeCompanion.Chat

  self.bufnr = self.create_buf()
  self.aug = api.nvim_create_augroup(CONSTANTS.AUTOCMD_GROUP .. ":" .. self.bufnr, {
    clear = false,
  })

  -- NOTE: Put the parser on the chat buffer for performance reasons
  local ok, chat_parser, yaml_parser
  ok, chat_parser = pcall(vim.treesitter.get_parser, self.bufnr, "markdown")
  if not ok then
    return log:error("[chat::init::new] Could not find the Markdown Tree-sitter parser")
  end
  self.chat_parser = chat_parser

  if show_settings then
    ok, yaml_parser = pcall(vim.treesitter.get_parser, self.bufnr, "yaml", { ignore_injections = false })
    if not ok then
      return log:error("Could not find the Yaml Tree-sitter parser")
    end
    self.yaml_parser = yaml_parser
  end

  self.builder = require("codecompanion.strategies.chat.ui.builder").new({ chat = self })
  self.context = require("codecompanion.strategies.chat.context").new({ chat = self })
  self.subscribers = require("codecompanion.strategies.chat.subscribers").new()
  self.tools = require("codecompanion.strategies.chat.tools").new({ bufnr = self.bufnr, messages = self.messages })
  self.tool_registry = require("codecompanion.strategies.chat.tool_registry").new({ chat = self })
  self.variables = require("codecompanion.strategies.chat.variables").new()
  self.watched_buffers = require("codecompanion.strategies.chat.watchers").new()

  table.insert(_G.codecompanion_buffers, self.bufnr)
  chatmap[self.bufnr] = {
    name = "Chat " .. vim.tbl_count(chatmap) + 1,
    description = CONSTANTS.BLANK_DESC,
    strategy = "chat",
    chat = self,
  }

  if args.adapter and adapters.resolved(args.adapter) then
    self.adapter = args.adapter
  else
    self.adapter = adapters.resolve(args.adapter or config.strategies.chat.adapter)
  end
  if not self.adapter then
    return log:error("No adapter found")
  end
  util.fire("ChatAdapter", {
    adapter = adapters.make_safe(self.adapter),
    bufnr = self.bufnr,
    id = self.id,
  })
  util.fire(
    "ChatModel",
    { bufnr = self.bufnr, id = self.id, model = self.adapter.schema and self.adapter.schema.model.default }
  )

  if self.adapter.type == "http" then
    self:apply_settings(schema.get_default(self.adapter, args.settings))
  end

  self.ui = require("codecompanion.strategies.chat.ui").new({
    adapter = self.adapter,
    chat_id = self.id,
    chat_bufnr = self.bufnr,
    roles = { user = user_role, llm = llm_role },
    settings = self.settings,
    window_opts = args.window_opts,
  })

  self:update_metadata()

  -- Likely this hasn't been set by the time the user opens the chat buffer
  if not _G.codecompanion_current_context then
    _G.codecompanion_current_context = self.buffer_context.bufnr
  end

  if args.messages then
    self.messages = args.messages
  end

  self.close_last_chat()
  self.ui:open():render(self.buffer_context, self.messages, { stop_context_insertion = args.stop_context_insertion })

  -- Set the header line for the chat buffer
  if args.messages and vim.tbl_count(args.messages) > 0 then
    local header_line = parser.headers(self, self.chat_parser)
    self.header_line = header_line and (header_line + 1) or 1
  end

  if vim.tbl_isempty(self.messages) or not helpers.has_user_messages(args.messages) then
    self.ui:set_intro_msg(self.intro_message)
  end

  if config.strategies.chat.keymaps then
    -- Filter out any private keymaps
    local filtered_keymaps = {}
    for k, v in pairs(config.strategies.chat.keymaps) do
      if k:sub(1, 1) ~= "_" then
        filtered_keymaps[k] = v
      end
    end

    keymaps
      .new({
        bufnr = self.bufnr,
        callbacks = require("codecompanion.strategies.chat.keymaps"),
        data = self,
        keymaps = filtered_keymaps,
      })
      :set()
  end

  local slash_command_keymaps = helpers.slash_command_keymaps(config.strategies.chat.slash_commands)
  if vim.tbl_count(slash_command_keymaps) > 0 then
    keymaps
      .new({
        bufnr = self.bufnr,
        callbacks = require("codecompanion.strategies.chat.slash_commands.keymaps"),
        data = self,
        keymaps = slash_command_keymaps,
      })
      :set()
  end

  ---@cast self CodeCompanion.Chat
  self:set_system_prompt()
  set_autocmds(self)

  last_chat = self

  for _, tool_name in pairs(config.strategies.chat.tools.opts.default_tools or {}) do
    local tool_config = config.strategies.chat.tools[tool_name]
    if tool_config ~= nil then
      self.tool_registry:add(tool_name, tool_config)
    elseif config.strategies.chat.tools.groups[tool_name] ~= nil then
      self.tool_registry:add_group(tool_name, config.strategies.chat.tools)
    end
  end

  -- Handle callbacks
  if args.callbacks then
    for event, callback_list in pairs(args.callbacks) do
      if type(callback_list) == "function" then
        -- Single callback
        self:add_callback(event, callback_list)
      elseif type(callback_list) == "table" then
        -- Array of callbacks
        for _, callback in ipairs(callback_list) do
          self:add_callback(event, callback)
        end
      end
    end
  end

  -- Set up subscriber callbacks
  self:add_callback("on_ready", function(c)
    c.subscribers:process(c)
  end)
  self:add_callback("on_cancelled", function(c)
    c.subscribers:stop()
  end)
  self:add_callback("on_closed", function(c)
    c.subscribers:stop()
  end)

  self:dispatch("on_created")

  util.fire("ChatCreated", { bufnr = self.bufnr, from_prompt_library = self.from_prompt_library, id = self.id })
  if args.auto_submit then
    self:submit()
  end

  return self ---@type CodeCompanion.Chat
end

---Add a callback for a specific event
---@param event string The event name
---@param callback fun(chat: CodeCompanion.Chat) The callback function
---@return CodeCompanion.Chat
function Chat:add_callback(event, callback)
  if not self.callbacks[event] then
    self.callbacks[event] = {}
  end
  if type(callback) == "function" then
    table.insert(self.callbacks[event], callback)
  end
  return self
end

---Dispatch callbacks for a specific event
---@param event string The event name
---@param ... any Additional arguments to pass to callbacks
---@return CodeCompanion.Chat
function Chat:dispatch(event, ...)
  local callbacks = self.callbacks[event]
  if not callbacks then
    return self
  end

  for _, callback in ipairs(callbacks) do
    local ok, err = pcall(callback, self, ...)
    if not ok then
      log:error("Callback error for %s: %s", event, err)
    end
  end
  return self
end

---Format and apply settings to the chat buffer
---@param settings? table
---@return CodeCompanion.Chat
function Chat:apply_settings(settings)
  if self.adapter.type ~= "http" then
    return self
  end

  self.settings = settings or schema.get_default(self.adapter)
  return self
end

---Change the adapter in the chat buffer
---@param name string
---@param model? string
function Chat:change_adapter(name, model)
  local function fire()
    return util.fire("ChatAdapter", { bufnr = self.bufnr, adapter = adapters.make_safe(self.adapter) })
  end

  self.adapter = require("codecompanion.adapters").resolve(name)
  self.ui.adapter = self.adapter

  if model then
    self:apply_model(model)
    return fire()
  end

  self:set_system_prompt()
  self:update_metadata()
  self:apply_settings()
  fire()
end

---Set a model in the chat buffer
---@param model string
---@return CodeCompanion.Chat
function Chat:apply_model(model)
  if self.adapter.type ~= "http" then
    return self
  end

  self.settings.model = model
  self.adapter.schema.model.default = model
  self.adapter = adapters.set_model(self.adapter)
  self:set_system_prompt()
  self:update_metadata()
  self:apply_settings()

  return self
end

---The source to provide the model entries for completion (cmp only)
---@param callback fun(request: table)
---@return nil
function Chat:complete_models(callback)
  if self.adapter.type ~= "http" then
    return
  end

  local items = {}
  local cursor = api.nvim_win_get_cursor(0)
  local key_name, node = parser.get_settings_key(self, { pos = { cursor[1] - 1, 1 } })
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
---@params prompt? string
---@params opts? table
---@return CodeCompanion.Chat
function Chat:set_system_prompt(prompt, opts)
  if self.opts and self.opts.ignore_system_prompt then
    return self
  end

  prompt = prompt or config.strategies.chat.opts.system_prompt
  opts = opts or { visible = false, tag = "system_prompt_from_config" }

  -- If the system prompt already exists, update it
  if helpers.has_tag(opts.tag, self.messages) then
    self:remove_tagged_message(opts.tag)
  end

  -- Workout in the message stack the last system prompt is
  local index
  if not opts.index then
    for i = #self.messages, 1, -1 do
      if self.messages[i].role == config.constants.SYSTEM_ROLE then
        index = i + 1
        break
      end
    end
  end

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
    system_prompt.cycle = self.cycle
    system_prompt.opts = opts

    table.insert(self.messages, index or opts.index or 1, system_prompt)
  end

  return self
end

---Toggle the system prompt in the chat buffer
---@return nil
function Chat:toggle_system_prompt()
  local has_system_prompt = vim.tbl_contains(
    vim.tbl_map(function(msg)
      return msg.opts.tag
    end, self.messages),
    "system_prompt_from_config"
  )

  if has_system_prompt then
    self:remove_tagged_message("system_prompt_from_config")
    util.notify("Removed system prompt")
  else
    self:set_system_prompt()
    util.notify("Added system prompt")
  end
end

---Remove a message with a given tag
---@param tag string
---@return nil
function Chat:remove_tagged_message(tag)
  self.messages = vim
    .iter(self.messages)
    :filter(function(msg)
      if msg.opts and msg.opts.tag == tag then
        return false
      end
      return true
    end)
    :totable()
end

---Add a message to the message table
---@param data { role: string, content: string, reasoning?: CodeCompanion.Chat.Reasoning, tool_calls?: CodeCompanion.Chat.ToolCall[] }
---@param opts? table Options for the message
---@return CodeCompanion.Chat
function Chat:add_message(data, opts)
  opts = opts or { visible = true }
  if opts.visible == nil then
    opts.visible = true
  end

  ---@type CodeCompanion.Chat.Message
  local message = {
    id = 1,
    _meta = {},
    role = data.role,
    content = data.content,
    reasoning = data.reasoning,
    cycle = self.cycle,
    tool_calls = data.tool_calls,
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
function Chat:replace_vars_and_tools(message)
  if self.tools:parse(self, message) then
    message.content = self.tools:replace(message.content)
  end
  if self.variables:parse(self, message) then
    message.content = self.variables:replace(message.content, self.buffer_context.bufnr)
  end
end

---Make a request to the LLM using the HTTP client
---@param payload table The payload to send to the LLM
---@return nil
function Chat:_submit_http(payload)
  local adapter = self.adapter ---@cast adapter CodeCompanion.HTTPAdapter

  if show_settings then
    local settings = parser.settings(self.bufnr, self.yaml_parser, adapter)
    helpers.apply_settings_and_model(self, settings)
  end

  local mapped_settings = adapter:map_schema_to_params(self.settings)
  log:trace("Settings:\n%s", mapped_settings)

  local output, reasoning, tools = {}, {}, {}

  local function process_chunk(data)
    if adapter.features.tokens then
      local tokens = adapter.handlers.tokens(adapter, data)
      if tokens then
        self.ui.tokens = tokens
      end
    end

    local result = adapter.handlers.chat_output(adapter, data, tools)
    if result and result.status then
      self.status = result.status
      if self.status == CONSTANTS.STATUS_SUCCESS then
        if result.output.role then
          result.output.role = config.constants.LLM_ROLE
          self._last_role = result.output.role
        end
        if result.output.reasoning then
          table.insert(reasoning, result.output.reasoning)
          self:add_buf_message({
            role = config.constants.LLM_ROLE,
            content = result.output.reasoning.content,
          }, { type = self.MESSAGE_TYPES.REASONING_MESSAGE })
        end
        table.insert(output, result.output.content)
        self:add_buf_message({
          role = config.constants.LLM_ROLE,
          content = result.output.content,
        }, { type = self.MESSAGE_TYPES.LLM_MESSAGE })
      elseif self.status == CONSTANTS.STATUS_ERROR then
        log:error("[chat::_submit_http] Error: %s", result.output)
        self:done(output)
      end
    end
  end

  local handle = get_client(adapter).new({ adapter = mapped_settings }):send(payload, {
    on_chunk = function(data)
      process_chunk(data)
    end,
    on_done = function(_)
      self:done(output, reasoning, tools)
    end,
    on_error = function(err)
      if self.status == CONSTANTS.STATUS_CANCELLING then
        return
      end
      self.status = CONSTANTS.STATUS_ERROR
      log:error("[chat::_submit_http] Error: %s", (err and (err.stderr or err.message)) or "unknown")
      self:done(output)
    end,
    bufnr = self.bufnr,
    strategy = "chat",
  })

  self.current_request = handle
end

---Make a request to the LLM using the ACP client
---@param payload table The payload to send to the LLM
---@return nil
function Chat:_submit_acp(payload)
  local acp_handler = require("codecompanion.strategies.chat.acp.handler").new(self)
  self.current_request = acp_handler:submit(payload)
end

---Submit the chat buffer's contents to the LLM
---@param opts? table
---@return nil
function Chat:submit(opts)
  if self.current_request then
    return log:debug("Chat request already in progress")
  end

  opts = opts or {}

  if opts.callback then
    opts.callback()
  end

  -- Refresh tools before submitting to pick up any dynamically added tools
  self.tools:refresh()

  if opts.auto_submit then
    self.watched_buffers:check_for_changes(self)
  else
    local message_to_submit = parser.messages(self, self.header_line)
    if not message_to_submit and not helpers.has_user_messages(self.messages) then
      return log:warn("No messages to submit")
    end

    self.watched_buffers:check_for_changes(self)

    -- Allow users to send a blank message to the LLM
    if not opts.regenerate then
      local chat_opts = config.strategies.chat.opts
      if message_to_submit and message_to_submit.content and chat_opts and chat_opts.prompt_decorator then
        message_to_submit.content =
          chat_opts.prompt_decorator(message_to_submit.content, adapters.make_safe(self.adapter), self.buffer_context)
      end
      self:add_message({
        role = config.constants.USER_ROLE,
        content = (message_to_submit and message_to_submit.content or config.strategies.chat.opts.blank_prompt),
      })
    end

    -- NOTE: There are instances when submit is called with no user message.
    -- Such as when tools auto-submitting responses. So, we need to ensure
    -- that we only manage context if the last message was from the user.
    if message_to_submit then
      message_to_submit = self.context:remove(self.messages[#self.messages])
      self:replace_vars_and_tools(message_to_submit)
      self:check_images(message_to_submit)
      self:check_context()
      add_pins(self)
    end

    -- Check if the user has manually overridden the adapter
    if vim.g.codecompanion_adapter and self.adapter.name ~= vim.g.codecompanion_adapter then
      self.adapter = adapters.resolve(config.adapters[vim.g.codecompanion_adapter])
    end

    if not config.display.chat.auto_scroll then
      vim.cmd("stopinsert")
    end
    self.ui:lock_buf()
    set_text_editing_area(self, 2) -- this accounts for the LLM header
  end

  local payload = {
    messages = self.adapter:map_roles(vim.deepcopy(self.messages)),
    tools = (not vim.tbl_isempty(self.tool_registry.schemas) and { self.tool_registry.schemas } or {}),
  }

  log:trace("Messages:\n%s", payload.messages)
  log:trace("Tools:\n%s", payload.tools)
  log:info("Chat request started")

  self:dispatch("on_submitted", { payload = payload })

  if self.adapter.type == "http" then
    self:_submit_http(payload)
  elseif self.adapter.type == "acp" then
    self:_submit_acp(payload)
  end

  util.fire("ChatSubmitted", { bufnr = self.bufnr, id = self.id, type = self.adapter.type })
end

---Method to fire when all the tools are done
---@param opts? table
---@return nil
function Chat:tools_done(opts)
  opts = opts or {}
  return ready_chat_buffer(self, opts)
end

---Label messages that have been sent to the LLM, by the user. For adapters that
---store state on our behalf, this prevents us from sending the same message
---multiple times.
---@return nil
function Chat:label_sent_items()
  vim.iter(self.messages):each(function(msg)
    if msg.role == config.constants.USER_ROLE and (msg._meta and not msg._meta.sent) then
      msg._meta.sent = true
    end
  end)
end

---Method to call after the response from the LLM is received
---@param output? table The message output from the LLM
---@param reasoning? table The reasoning output from the LLM
---@param tools? table The tools output from the LLM
---@param status? "stopped" The reason the done method was called
---@return nil
function Chat:done(output, reasoning, tools, status)
  self.current_request = nil

  -- Commonly, a status may not be set if the message exceeds a token limit
  if not self.status or self.status == "" then
    return self:reset()
  end
  local has_output = output and not vim.tbl_isempty(output)
  local has_tools = tools and not vim.tbl_isempty(tools)

  local content
  if has_output then
    content = vim.trim(table.concat(output or {}, ""))
  end

  local reasoning_content = nil
  if reasoning and not vim.tbl_isempty(reasoning) then
    if self.adapter.handlers.form_reasoning then
      reasoning_content = self.adapter.handlers.form_reasoning(self.adapter, reasoning)
    end
  end

  if content and content ~= "" then
    self:add_message({
      role = config.constants.LLM_ROLE,
      content = content,
      reasoning = reasoning_content,
    })
    reasoning_content = nil
  end

  -- If a user stops the request, we should be prepared to send the last message
  -- again as we can't be sure what the LLM had actually received
  if not status or status ~= "stopped" then
    self:label_sent_items()
  end

  -- Process tools last
  if has_tools then
    tools = self.adapter.handlers.tools.format_tool_calls(self.adapter, tools)
    self:add_message({
      role = config.constants.LLM_ROLE,
      reasoning = reasoning_content,
      tool_calls = tools,
    }, {
      visible = false,
    })
    return self.tools:execute(self, tools)
  end

  ready_chat_buffer(self)

  self:dispatch("on_completed", { status = self.status })
  util.fire("ChatDone", { bufnr = self.bufnr, id = self.id })
end

---Add context to the chat buffer (Useful for user's adding custom Slash Commands)
---@param data { role?: string, content: string }
---@param source string The source of the context
---@param id string The uniqie ID linkin the context to the message
---@param opts? { bufnr: number, context_opts: table, path: string, tag: string, visible: boolean}
function Chat:add_context(data, source, id, opts)
  opts = vim.tbl_extend("force", { context_id = id, visible = false }, opts or {})

  if not data.role then
    data.role = config.constants.USER_ROLE
  end

  -- Context is created by adding it to the context class and linking it to a message on the chat buffer
  self.context:add({ source = source, id = id, bufnr = opts.bufnr, path = opts.path, opts = opts.context_opts })
  self:add_message(data, { context_id = id, tag = opts.tag or source, visible = opts.visible })
end

---TODO: Remove this method in v18.0.0
---Add a reference to the chat buffer (Useful for user's adding custom Slash Commands)
---@param data { role: string, content: string }
---@param source string
---@param id string
---@param opts? table Options for the message
function Chat:add_reference(data, source, id, opts)
  vim.deprecate(
    "`Chat:add_reference` is now deprecated.",
    "Please use `chat:add_context` instead",
    "v18.0.0",
    "CodeCompanion",
    false
  )

  return self:add_context(data, source, id, opts)
end

---Check if there are any images in the chat buffer
---@param message table
---@return nil
function Chat:check_images(message)
  local images = parser.images(self, self.header_line)
  if not images then
    return
  end

  for _, image in ipairs(images) do
    local encoded_image = helpers.encode_image(image)
    if type(encoded_image) == "string" then
      log:warn("Could not encode image: %s", encoded_image)
    else
      helpers.add_image(self, encoded_image)

      -- Replace the image link in the message with "image"
      local to_remove = fmt("[Image](%s)", image.path)
      message.content = vim.trim(message.content:gsub(vim.pesc(to_remove), "image"))
    end
  end
end

---Reconcile the context_items table to the items in the chat buffer
---@return nil
function Chat:check_context()
  local context_in_chat = self.context:get_from_chat()
  if vim.tbl_isempty(context_in_chat) and vim.tbl_isempty(self.context_items) then
    return
  end

  local function expand_group_ref(group_name)
    local group_config = self.tools.tools_config.groups[group_name] or {}
    return vim.tbl_map(function(tool)
      return "<tool>" .. tool .. "</tool>"
    end, group_config.tools or {})
  end

  local groups_in_chat = {}
  for _, id in ipairs(context_in_chat) do
    local group_name = id:match("<group>(.*)</group>")
    if group_name and vim.trim(group_name) ~= "" then
      table.insert(groups_in_chat, group_name)
    end
  end
  -- Populate the context_in_chat with tool refs from groups
  vim.iter(groups_in_chat):each(function(group_name)
    vim.list_extend(context_in_chat, expand_group_ref(group_name))
  end)

  -- Fetch context items that exist on the chat object but not in the buffer
  local to_remove = vim
    .iter(self.context_items)
    :filter(function(ctx)
      return not vim.tbl_contains(context_in_chat, ctx.id)
    end)
    :map(function(ctx)
      return ctx.id
    end)
    :totable()

  if vim.tbl_isempty(to_remove) then
    return
  end

  local groups_to_remove = vim.tbl_filter(function(id)
    return id:match("<group>(.*)</group>")
  end, to_remove)

  -- Extend to_remove with tools in the groups
  vim.iter(groups_to_remove):each(function(group_name)
    vim.list_extend(to_remove, expand_group_ref(group_name))
  end)

  -- Remove them from the messages table
  self.messages = vim
    .iter(self.messages)
    :filter(function(msg)
      if msg.opts and msg.opts.context_id and vim.tbl_contains(to_remove, msg.opts.context_id) then
        return false
      end
      return true
    end)
    :totable()

  -- And from the context_items table
  self.context_items = vim
    .iter(self.context_items)
    :filter(function(ctx)
      return not vim.tbl_contains(to_remove, ctx.id)
    end)
    :totable()

  -- Clear any tool's schemas
  local schemas_to_keep = {}
  local tools_in_use_to_keep = {}
  for id, tool_schema in pairs(self.tool_registry.schemas) do
    if not vim.tbl_contains(to_remove, id) then
      schemas_to_keep[id] = tool_schema
      local tool_name = id:match("<tool>(.*)</tool>")
      if tool_name and self.tool_registry.in_use[tool_name] then
        tools_in_use_to_keep[tool_name] = true
      end
    else
      log:debug("Removing tool schema and usage flag for ID: %s", id) -- Optional logging
    end
  end
  self.tool_registry.schemas = schemas_to_keep
  self.tool_registry.in_use = tools_in_use_to_keep
end

---Refresh the chat context by syncing to message-linked context IDs and re-rendering
---@return CodeCompanion.Chat
function Chat:refresh_context()
  -- Collect the set of context IDs still referenced by messages
  local ids_in_messages = {}
  for _, msg in ipairs(self.messages or {}) do
    if msg.opts and msg.opts.context_id then
      ids_in_messages[msg.opts.context_id] = true
    end
  end

  -- Keep only context items that are still referenced by messages
  if self.context_items and not vim.tbl_isempty(self.context_items) then
    self.context_items = vim
      .iter(self.context_items)
      :filter(function(ctx)
        return ids_in_messages[ctx.id] == true
      end)
      :totable()
  end

  -- Clear currently rendered Context block and re-render
  self.context:clear_rendered()
  self.context:render()

  return self
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
  self.status = CONSTANTS.STATUS_CANCELLING
  self:dispatch("on_cancelled")
  util.fire("ChatStopped", { bufnr = self.bufnr, id = self.id })

  if self.current_tool then
    local tool_job = self.current_tool
    self.current_tool = nil

    _G.codecompanion_cancel_tool = true
    pcall(function()
      tool_job:shutdown()
    end)
  end

  if self.current_request then
    print("Cancelling request...")
    local handle = self.current_request
    self.current_request = nil

    pcall(function()
      if handle and type(handle.cancel) == "function" then
        print("Should be cancelled")
        handle.cancel()
      end
    end)

    if self.adapter.handlers and self.adapter.handlers.on_exit then
      self.adapter.handlers.on_exit(self.adapter)
    end
  end

  vim.schedule(function()
    log:debug("Chat request cancelled")
    self:done(nil, nil, nil, "stopped")
  end)
end

---Close the current chat buffer and clean up any resources
---@return nil
function Chat:close()
  if self.current_request then
    self:stop()
  end

  self:dispatch("on_closed")

  edit_tracker.handle_chat_close(self)
  edit_tracker.clear(self)

  if last_chat and last_chat.bufnr == self.bufnr then
    last_chat = nil
  end

  util.fire("ChatClosed", { bufnr = self.bufnr, id = self.id })
  util.fire("ChatAdapter", { bufnr = self.bufnr, id = self.id, adapter = nil })
  util.fire("ChatModel", { bufnr = self.bufnr, id = self.id, model = nil })

  table.remove(
    _G.codecompanion_buffers,
    vim.iter(_G.codecompanion_buffers):enumerate():find(function(_, v)
      return v == self.bufnr
    end)
  )
  table.remove(
    _G.codecompanion_chat_metadata,
    vim.iter(_G.codecompanion_chat_metadata):enumerate():find(function(_, v)
      return v == self.bufnr
    end)
  )
  chatmap[self.bufnr] = nil
  pcall(api.nvim_buf_delete, self.bufnr, { force = true })
  if self.aug then
    api.nvim_clear_autocmds({ group = self.aug })
  end
  if self.ui.aug then
    api.nvim_clear_autocmds({ group = self.ui.aug })
  end
  if self.adapter.type == "acp" and self.acp_connection then
    self.acp_connection:disconnect()
  end

  self = nil
end

---Add a message directly to the chat buffer that will be visible to the user
---This will NOT form part of the message stack that is sent to the LLM
---@param data table
---@param opts? table
function Chat:add_buf_message(data, opts)
  assert(type(data) == "table", "data must be a table")
  opts = opts or {}

  self.builder:add_message(data, opts)
end

---Add the output from a tool to the message history and a message to the UI
---@param tool table The Tool that was executed
---@param for_llm string The output to share with the LLM
---@param for_user? string The output to share with the user. If empty will use the LLM's output
---@return nil
function Chat:add_tool_output(tool, for_llm, for_user)
  local tool_call = tool.function_call
  log:debug("Tool output: %s", tool_call)

  local output = self.adapter.handlers.tools.output_response(self.adapter, tool_call, for_llm)
  output.cycle = self.cycle
  output.id = make_id({ role = output.role, content = output.content })
  output.opts = vim.tbl_extend("force", output.opts or {}, {
    visible = true,
  })

  -- Ensure that tool output is merged if it has the same tool call ID
  local existing = find_tool_call(tool_call.id, self.messages)
  if existing then
    if existing.content ~= "" then
      existing.content = existing.content .. "\n\n" .. output.content
    else
      existing.content = output.content
    end
  else
    table.insert(self.messages, output)
  end

  -- Allow tools to pass in an empty string to not write any output to the buffer
  if for_user == "" then
    return
  end

  self:add_buf_message({
    role = config.constants.LLM_ROLE,
    content = (for_user or for_llm),
  }, {
    type = self.MESSAGE_TYPES.TOOL_MESSAGE,
  })
end

---When a request has finished, reset the chat buffer
---@return nil
function Chat:reset()
  self.status = ""
  self.ui:unlock_buf()
end

---Get currently focused code block or the last one in the chat buffer
---@return TSNode | nil
function Chat:get_codeblock()
  local cursor = api.nvim_win_get_cursor(0)
  return parser.codeblock(self, cursor)
end

---Clear the chat buffer
---@return nil
function Chat:clear()
  self.cycle = 1
  self.header_line = 1
  self.messages = {}
  self.context_items = {}

  self.tool_registry:clear()

  log:trace("Clearing chat buffer")
  self.ui:render(self.buffer_context, self.messages, self.opts):set_intro_msg(self.intro_message)
  self:set_system_prompt()
  util.fire("ChatCleared", { bufnr = self.bufnr, id = self.id })
end

---Display the chat buffer's settings and messages
function Chat:debug()
  if vim.tbl_isempty(self.messages) then
    return
  end

  return self.settings, self.messages
end

---Update a global state object that users can access in their config
---@return nil
function Chat:update_metadata()
  local model
  if self.adapter.type == "http" then
    model = self.adapter.schema and self.adapter.schema.model and self.adapter.schema.model.default
  end

  _G.codecompanion_chat_metadata[self.bufnr] = {
    adapter = {
      name = self.adapter.formatted_name,
      model = model,
    },
    context_items = #self.context_items,
    cycles = self.cycle,
    id = self.id,
    tokens = self.ui.tokens or 0,
    tools = vim.tbl_count(self.tool_registry.in_use) or 0,
  }
end

---Returns the chat object(s) based on the buffer number
---@param bufnr? number
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
  -- if last_chat buffer was deleted, we need to clean it out
  if last_chat and not api.nvim_buf_is_loaded(last_chat.bufnr) then
    last_chat:close()
    last_chat = nil
    return nil
  end
  return last_chat
end

---Close the last chat buffer
---@return nil
function Chat.close_last_chat()
  if last_chat and not vim.tbl_isempty(last_chat) then
    if last_chat.ui:is_visible() then
      last_chat.ui:hide()
    end
  end
end

return Chat
