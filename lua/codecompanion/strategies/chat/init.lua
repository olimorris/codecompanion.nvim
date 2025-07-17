--=============================================================================
-- The Chat Buffer - Where all of the logic for conversing with an LLM sits
--=============================================================================

---@class CodeCompanion.Chat
---@field adapter CodeCompanion.Adapter The adapter to use for the chat
---@field agents CodeCompanion.Agent The agent that calls tools available to the user
---@field builder CodeCompanion.Chat.UI.Builder The builder for the chat UI
---@field aug number The ID for the autocmd group
---@field bufnr integer The buffer number of the chat
---@field context table The context of the buffer that the chat was initiated from
---@field current_request table|nil The current request being executed
---@field current_tool table The current tool being executed
---@field cycle number Records the number of turn-based interactions (User -> LLM) that have taken place
---@field header_line number The line number of the user header that any Tree-sitter parsing should start from
---@field from_prompt_library? boolean Whether the chat was initiated from the prompt library
---@field header_ns integer The namespace for the virtual text that appears in the header
---@field id integer The unique identifier for the chat
---@field messages? table The messages in the chat buffer
---@field opts CodeCompanion.ChatArgs Store all arguments in this table
---@field parser vim.treesitter.LanguageTree The Markdown Tree-sitter parser for the chat buffer
---@field references CodeCompanion.Chat.References
---@field refs? table<CodeCompanion.Chat.Ref> References which are sent to the LLM e.g. buffers, slash command output
---@field settings? table The settings that are used in the adapter of the chat buffer
---@field subscribers table The subscribers to the chat buffer
---@field tokens? nil|number The number of tokens in the chat
---@field tools CodeCompanion.Chat.Tools Methods for handling interactions between the chat buffer and tools
---@field ui CodeCompanion.Chat.UI The UI of the chat buffer
---@field variables? CodeCompanion.Variables The variables available to the user
---@field watchers CodeCompanion.Watchers The buffer watcher instance
---@field yaml_parser vim.treesitter.LanguageTree The Yaml Tree-sitter parser for the chat buffer
---@field _last_role string The last role that was rendered in the chat buffer

---@class CodeCompanion.ChatArgs Arguments that can be injected into the chat
---@field adapter? CodeCompanion.Adapter The adapter used in this chat buffer
---@field auto_submit? boolean Automatically submit the chat when the chat buffer is created
---@field context? table Context of the buffer that the chat was initiated from
---@field from_prompt_library? boolean Whether the chat was initiated from the prompt library
---@field ignore_system_prompt? boolean Do not send the default system prompt with the request
---@field last_role string The last role that was rendered in the chat buffer-
---@field messages? table The messages to display in the chat buffer
---@field settings? table The settings that are used in the adapter of the chat buffer
---@field status? string The status of any running jobs in the chat buffe
---@field stop_context_insertion? boolean Stop any visual selection from being automatically inserted into the chat buffer
---@field tokens? table Total tokens spent in the chat buffer so far

local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local completion = require("codecompanion.providers.completion")
local config = require("codecompanion.config")
local hash = require("codecompanion.utils.hash")
local helpers = require("codecompanion.strategies.chat.helpers")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local schema = require("codecompanion.schema")
local util = require("codecompanion.utils")
local yaml = require("codecompanion.utils.yaml")

local api = vim.api
local get_node_text = vim.treesitter.get_node_text --[[@type function]]
local get_query = vim.treesitter.query.get --[[@type function]]

local CONSTANTS = {
  AUTOCMD_GROUP = "codecompanion.chat",

  STATUS_CANCELLING = "cancelling",
  STATUS_ERROR = "error",
  STATUS_SUCCESS = "success",

  BLANK_DESC = "[No messages]",
}

local llm_role = config.strategies.chat.roles.llm
local user_role = config.strategies.chat.roles.user

--=============================================================================
-- Private methods
--=============================================================================

---Add updated content from the pins to the chat buffer
---@param chat CodeCompanion.Chat
---@return nil
local function add_pins(chat)
  local pins = vim
    .iter(chat.refs)
    :filter(function(ref)
      return ref.opts.pinned
    end)
    :totable()

  if vim.tbl_isempty(pins) then
    return
  end

  for _, pin in ipairs(pins) do
    -- Don't add the pin twice in the same cycle
    local exists = false
    vim.iter(chat.messages):each(function(msg)
      if msg.opts and msg.opts.reference == pin.id and msg.cycle == chat.cycle then
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

---Find a message in the table that has a specific tool call ID
---@param id string
---@param messages table
---@return table|nil
local function find_tool_call(id, messages)
  for _, msg in ipairs(messages) do
    if msg.tool_call_id and msg.tool_call_id == id then
      return msg
    end
  end
  return nil
end

---Get the settings key at the current cursor position
---@param chat CodeCompanion.Chat
---@param opts? table
local function get_settings_key(chat, opts)
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
  local key_name = get_node_text(key_node, chat.bufnr)
  return key_name, node
end

---Determine if a tag exists in the messages table
---@param tag string
---@param messages table
---@return boolean
local function has_tag(tag, messages)
  return vim.tbl_contains(
    vim.tbl_map(function(msg)
      return msg.opts and msg.opts.tag
    end, messages),
    tag
  )
end

---Are there any user messages in the chat buffer?
---@param chat CodeCompanion.Chat
---@return boolean
local function has_user_messages(chat)
  local count = vim
    .iter(chat.messages)
    :filter(function(msg)
      return msg.role == config.constants.USER_ROLE
    end)
    :totable()
  if #count == 0 then
    return false
  end
  return true
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
    chat.ui:display_tokens(chat.parser, chat.header_line)
    chat.references:render()

    chat.subscribers:process(chat)
  end

  -- If we're automatically responding to a tool output, we need to leave some
  -- space for the LLM's response so we can then display the user prompt again
  if opts.auto_submit then
    chat.ui:add_line_break()
    chat.ui:add_line_break()
  end

  log:info("Chat request finished")
  chat:reset()
end

local _cached_settings = {}

---Parse the chat buffer for settings
---@param bufnr integer
---@param parser vim.treesitter.LanguageTree
---@param adapter? CodeCompanion.Adapter
---@return table
local function ts_parse_settings(bufnr, parser, adapter)
  if _cached_settings[bufnr] then
    return _cached_settings[bufnr]
  end

  -- If the user has disabled settings in the chat buffer, use the default settings
  if not config.display.chat.show_settings then
    if adapter then
      _cached_settings[bufnr] = adapter:make_from_schema()
      return _cached_settings[bufnr]
    end
  end

  local settings = {}

  local query = get_query("yaml", "chat")
  local root = parser:parse()[1]:root()

  local end_line = -1
  if adapter then
    -- Account for the two YAML lines and the fact Tree-sitter is 0-indexed
    end_line = vim.tbl_count(adapter.schema) + 2 - 1
  end

  for _, matches, _ in query:iter_matches(root, bufnr, 0, end_line) do
    local nodes = matches[1]
    local node = type(nodes) == "table" and nodes[1] or nodes

    local value = get_node_text(node, bufnr)

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
---@param chat CodeCompanion.Chat
---@param start_range number
---@return { content: string }|nil
local function ts_parse_messages(chat, start_range)
  local query = get_query("markdown", "chat")

  local tree = chat.parser:parse({ start_range - 1, -1 })[1]
  local root = tree:root()

  local content = {}
  local last_role = nil

  for id, node in query:iter_captures(root, chat.bufnr, start_range - 1, -1) do
    if query.captures[id] == "role" then
      last_role = helpers.format_role(get_node_text(node, chat.bufnr))
    elseif last_role == user_role and query.captures[id] == "content" then
      table.insert(content, get_node_text(node, chat.bufnr))
    end
  end

  content = helpers.strip_references(content) -- If users send a blank message to the LLM, sometimes references are included
  if not vim.tbl_isempty(content) then
    return { content = vim.trim(table.concat(content, "\n\n")) }
  end

  return nil
end

---Parse the chat buffer for the last header
---@param chat CodeCompanion.Chat
---@return number|nil
local function ts_parse_headers(chat)
  local query = get_query("markdown", "chat")

  local tree = chat.parser:parse({ 0, -1 })[1]
  local root = tree:root()

  local last_match = nil
  for id, node in query:iter_captures(root, chat.bufnr) do
    if query.captures[id] == "role_only" then
      local role = helpers.format_role(get_node_text(node, chat.bufnr))
      if role == user_role then
        last_match = node
      end
    end
  end

  if last_match then
    return last_match:range()
  end
end

---Parse a section of the buffer for Markdown inline links.
---@param chat CodeCompanion.Chat The chat instance.
---@param start_range number The 1-indexed line number from where to start parsing.
local function ts_parse_images(chat, start_range)
  local ts_query = vim.treesitter.query.parse(
    "markdown_inline",
    [[
((inline_link) @link)
  ]]
  )
  local parser = vim.treesitter.get_parser(chat.bufnr, "markdown_inline")

  local tree = parser:parse({ start_range, -1 })[1]
  local root = tree:root()

  local links = {}

  for id, node in ts_query:iter_captures(root, chat.bufnr, start_range - 1, -1) do
    local capture_name = ts_query.captures[id]
    if capture_name == "link" then
      local link_label_text = nil
      local link_dest_text = nil

      for child in node:iter_children() do
        local child_type = child:type()

        if child_type == "link_text" then
          local text = vim.treesitter.get_node_text(child, chat.bufnr)
          link_label_text = text
        elseif child_type == "link_destination" then
          local text = vim.treesitter.get_node_text(child, chat.bufnr)
          link_dest_text = text
        end
      end

      if link_label_text and link_dest_text then
        table.insert(links, { text = link_label_text, path = link_dest_text })
      end
    end
  end

  if vim.tbl_isempty(links) then
    return nil
  end

  return links
end

---Parse the chat buffer for a code block
---returns the code block that the cursor is in or the last code block
---@param chat CodeCompanion.Chat
---@param cursor? table
---@return TSNode | nil
local function ts_parse_codeblock(chat, cursor)
  local root = chat.parser:parse()[1]:root()
  local query = get_query("markdown", "chat")
  if query == nil then
    return nil
  end

  local last_match = nil
  for id, node in query:iter_captures(root, chat.bufnr, 0, -1) do
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

  if config.display.chat.show_settings then
    api.nvim_create_autocmd("CursorMoved", {
      group = chat.aug,
      buffer = bufnr,
      desc = "Show settings information in the CodeCompanion chat buffer",
      callback = function()
        local key_name, node = get_settings_key(chat)
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
        local settings = ts_parse_settings(bufnr, chat.yaml_parser, chat.adapter)

        local errors = schema.validate(chat.adapter.schema, settings, chat.adapter)
        local node = settings.__ts_node

        local items = {}
        if errors and node then
          for child in node:iter_children() do
            assert(child:type() == "block_mapping_pair")
            local key = get_node_text(child:named_child(0), chat.bufnr)
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
    context = args.context,
    cycle = 1,
    header_line = 1,
    from_prompt_library = args.from_prompt_library or false,
    id = id,
    messages = args.messages or {},
    opts = args,
    refs = {},
    status = "",
    create_buf = function()
      local bufnr = api.nvim_create_buf(false, true)
      api.nvim_buf_set_name(bufnr, string.format("[CodeCompanion] %d", id))
      vim.bo[bufnr].filetype = "codecompanion"

      return bufnr
    end,
    _last_role = args.last_role or config.constants.USER_ROLE,
  }, { __index = Chat })

  self.bufnr = self.create_buf()
  self.aug = api.nvim_create_augroup(CONSTANTS.AUTOCMD_GROUP .. ":" .. self.bufnr, {
    clear = false,
  })

  -- Assign the parsers to the chat object for performance
  local ok, parser, yaml_parser
  ok, parser = pcall(vim.treesitter.get_parser, self.bufnr, "markdown")
  if not ok then
    return log:error("Could not find the Markdown Tree-sitter parser")
  end
  self.parser = parser

  if config.display.chat.show_settings then
    ok, yaml_parser = pcall(vim.treesitter.get_parser, self.bufnr, "yaml", { ignore_injections = false })
    if not ok then
      return log:error("Could not find the Yaml Tree-sitter parser")
    end
    self.yaml_parser = yaml_parser
  end

  self.agents = require("codecompanion.strategies.chat.agents").new({ bufnr = self.bufnr, messages = self.messages })
  self.builder = require("codecompanion.strategies.chat.ui.builder").new({ chat = self })
  self.references = require("codecompanion.strategies.chat.references").new({ chat = self })
  self.subscribers = require("codecompanion.strategies.chat.subscribers").new()
  self.tools = require("codecompanion.strategies.chat.tools").new({ chat = self })
  self.variables = require("codecompanion.strategies.chat.variables").new()
  self.watchers = require("codecompanion.strategies.chat.watchers").new()

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
  util.fire("ChatModel", { bufnr = self.bufnr, id = self.id, model = self.adapter.schema.model.default })

  self:apply_settings(schema.get_default(self.adapter, args.settings))

  self.ui = require("codecompanion.strategies.chat.ui").new({
    adapter = self.adapter,
    chat_id = self.id,
    chat_bufnr = self.bufnr,
    roles = { user = user_role, llm = llm_role },
    settings = self.settings,
  })

  if args.messages then
    self.messages = args.messages
  end

  self.close_last_chat()
  self.ui:open():render(self.context, self.messages, args)

  -- Set the header line for the chat buffer
  if args.messages and vim.tbl_count(args.messages) > 0 then
    ---@cast self CodeCompanion.Chat
    local header_line = ts_parse_headers(self)
    self.header_line = header_line and (header_line + 1) or 1
  end

  if vim.tbl_isempty(self.messages) then
    self.ui:set_intro_msg()
  end

  if config.strategies.chat.keymaps then
    keymaps
      .new({
        bufnr = self.bufnr,
        callbacks = require("codecompanion.strategies.chat.keymaps"),
        data = self,
        keymaps = config.strategies.chat.keymaps,
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
  self:add_system_prompt()
  set_autocmds(self)

  last_chat = self

  for _, tool_name in pairs(config.strategies.chat.tools.opts.default_tools or {}) do
    local tool_config = config.strategies.chat.tools[tool_name]
    if tool_config ~= nil then
      self.tools:add(tool_name, tool_config)
    elseif config.strategies.chat.tools.groups[tool_name] ~= nil then
      self.tools:add_group(tool_name, config.strategies.chat.tools)
    end
  end

  util.fire("ChatCreated", { bufnr = self.bufnr, from_prompt_library = self.from_prompt_library, id = self.id })
  if args.auto_submit then
    self:submit()
  end

  return self ---@type CodeCompanion.Chat
end

---Format and apply settings to the chat buffer
---@param settings? table
---@return nil
function Chat:apply_settings(settings)
  self.settings = settings or schema.get_default(self.adapter)

  if not config.display.chat.show_settings then
    _cached_settings[self.bufnr] = self.settings
  end
end

---Set a model in the chat buffer
---@param model string
---@return self
function Chat:apply_model(model)
  if _cached_settings[self.bufnr] then
    _cached_settings[self.bufnr].model = model
  end

  self.adapter.schema.model.default = model
  self.adapter = adapters.set_model(self.adapter)

  return self
end

---The source to provide the model entries for completion (cmp only)
---@param callback fun(request: table)
---@return nil
function Chat:complete_models(callback)
  local items = {}
  local cursor = api.nvim_win_get_cursor(0)
  local key_name, node = get_settings_key(self, { pos = { cursor[1] - 1, 1 } })
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
function Chat:add_system_prompt(prompt, opts)
  if self.opts and self.opts.ignore_system_prompt then
    return self
  end

  opts = opts or { visible = false, tag = "from_config" }

  -- Don't add the same system prompt twice
  if has_tag(opts.tag, self.messages) then
    return self
  end

  -- Get the index of the last system prompt
  local index
  if not opts.index then
    for i = #self.messages, 1, -1 do
      if self.messages[i].role == config.constants.SYSTEM_ROLE then
        index = i + 1
        break
      end
    end
  end

  prompt = prompt or config.opts.system_prompt
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

    table.insert(self.messages, index or 1, system_prompt)
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
    "from_config"
  )

  if has_system_prompt then
    self:remove_tagged_message("from_config")
    util.notify("Removed system prompt")
  else
    self:add_system_prompt()
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
---@param data { role: string, content: string, reasoning?: table, tool_calls?: table }
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
    reasoning = data.reasoning,
    tool_calls = data.tool_calls,
  }
  message.id = make_id(message)
  message.cycle = self.cycle
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
  if self.agents:parse(self, message) then
    message.content = self.agents:replace(message.content)
  end
  if self.variables:parse(self, message) then
    message.content = self.variables:replace(message.content, self.context.bufnr)
  end
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

  -- Refresh agent tools before submitting to pick up any dynamically added tools
  self.agents:refresh_tools()

  local bufnr = self.bufnr

  if opts.auto_submit then
    self.watchers:check_for_changes(self)
  else
    local message = ts_parse_messages(self, self.header_line)

    if not message and not has_user_messages(self) then
      return log:warn("No messages to submit")
    end

    self.watchers:check_for_changes(self)

    -- Allow users to send a blank message to the LLM
    if not opts.regenerate then
      local chat_opts = config.strategies.chat.opts
      if message and message.content and chat_opts and chat_opts.prompt_decorator then
        message.content = chat_opts.prompt_decorator(message.content, adapters.make_safe(self.adapter), self.context)
      end
      self:add_message({
        role = config.constants.USER_ROLE,
        content = (message and message.content or config.strategies.chat.opts.blank_prompt),
      })
    end

    -- NOTE: There are instances when submit is called with no user message. Such
    -- as in the case of tools auto-submitting responses. References should be
    -- excluded and we can do this by checking for user messages.
    if message then
      message = self.references:clear(self.messages[#self.messages])
      self:replace_vars_and_tools(message)
      self:check_images(message)
      self:check_references()
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

  local settings = ts_parse_settings(bufnr, self.yaml_parser, self.adapter)
  self:apply_settings(settings)
  local mapped_settings = self.adapter:map_schema_to_params(settings)

  local payload = {
    messages = self.adapter:map_roles(vim.deepcopy(self.messages)),
    tools = (not vim.tbl_isempty(self.tools.schemas) and { self.tools.schemas } or {}),
  }

  log:trace("Settings:\n%s", mapped_settings)
  log:trace("Messages:\n%s", self.messages)
  log:trace("Tools:\n%s", payload.tools)
  log:info("Chat request started")

  local output = {}
  local reasoning = {}
  local tools = {}
  self.current_request = client.new({ adapter = mapped_settings }):request(payload, {
    ---@param err { message: string, stderr: string }
    ---@param data table
    ---@param adapter CodeCompanion.Adapter The modified adapter from the http client
    callback = function(err, data, adapter)
      if err and err.stderr ~= "{}" then
        self.status = CONSTANTS.STATUS_ERROR
        log:error("Error: %s", err.stderr)
        return self:done(output)
      end

      if data then
        if adapter.features.tokens then
          local tokens = self.adapter.handlers.tokens(adapter, data)
          if tokens then
            self.ui.tokens = tokens
          end
        end

        local result = self.adapter.handlers.chat_output(adapter, data, tools)
        if result and result.status then
          self.status = result.status
          if self.status == CONSTANTS.STATUS_SUCCESS then
            if result.output.role then
              self._last_role = result.output.role
              result.output.role = config.constants.LLM_ROLE
            end
            if result.output.reasoning then
              table.insert(reasoning, result.output.reasoning)
              self:add_buf_message(
                { role = result.output.role, content = result.output.reasoning.content },
                { type = self.MESSAGE_TYPES.REASONING_MESSAGE }
              )
            end
            table.insert(output, result.output.content)
            self:add_buf_message(
              { role = result.output.role, content = result.output.content },
              { type = self.MESSAGE_TYPES.LLM_MESSAGE }
            )
          elseif self.status == CONSTANTS.STATUS_ERROR then
            log:error("Error: %s", result.output)
            return self:done(output)
          end
        end
      end
    end,
    done = function()
      self:done(output, reasoning, tools)
    end,
  }, { bufnr = bufnr, strategy = "chat" })
  util.fire("ChatSubmitted", { bufnr = self.bufnr, id = self.id })
end

---Method to fire when all the tools are done
---@param opts? table
---@return nil
function Chat:tools_done(opts)
  opts = opts or {}
  return ready_chat_buffer(self, opts)
end

---Method to call after the response from the LLM is received
---@param output? table The message output from the LLM
---@param reasoning? table The reasoning output from the LLM
---@param tools? table The tools output from the LLM
---@return nil
function Chat:done(output, reasoning, tools)
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
    return self.agents:execute(self, tools)
  end

  ready_chat_buffer(self)
end

---Add a reference to the chat buffer (Useful for user's adding custom Slash Commands)
---@param data { role: string, content: string }
---@param source string
---@param id string
---@param opts? table Options for the message
function Chat:add_reference(data, source, id, opts)
  opts = opts or { reference = id, visible = false }

  self.references:add({ source = source, id = id })
  self:add_message(data, opts)
end

---Check if there are any images in the chat buffer
---@param message table
---@return nil
function Chat:check_images(message)
  local images = ts_parse_images(self, self.header_line)
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
      local to_remove = string.format("[Image](%s)", image.path)
      message.content = vim.trim(message.content:gsub(vim.pesc(to_remove), "image"))
    end
  end
end

---Reconcile the references table to the references in the chat buffer
---@return nil
function Chat:check_references()
  local refs_in_chat = self.references:get_from_chat()
  if vim.tbl_isempty(refs_in_chat) and vim.tbl_isempty(self.refs) then
    return
  end

  local function expand_group_ref(group_name)
    local group_config = self.agents.tools_config.groups[group_name] or {}
    return vim.tbl_map(function(tool)
      return "<tool>" .. tool .. "</tool>"
    end, group_config.tools or {})
  end

  local groups_in_chat = {}
  for _, id in ipairs(refs_in_chat) do
    local group_name = id:match("<group>(.*)</group>")
    if group_name and vim.trim(group_name) ~= "" then
      table.insert(groups_in_chat, group_name)
    end
  end
  -- Populate the refs_in_chat with tool refs from groups
  vim.iter(groups_in_chat):each(function(group_name)
    vim.list_extend(refs_in_chat, expand_group_ref(group_name))
  end)

  -- Fetch references that exist on the chat object but not in the buffer
  local to_remove = vim
    .iter(self.refs)
    :filter(function(ref)
      return not vim.tbl_contains(refs_in_chat, ref.id)
    end)
    :map(function(ref)
      return ref.id
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
      if msg.opts and msg.opts.reference and vim.tbl_contains(to_remove, msg.opts.reference) then
        return false
      end
      return true
    end)
    :totable()

  -- And from the refs table
  self.refs = vim
    .iter(self.refs)
    :filter(function(ref)
      return not vim.tbl_contains(to_remove, ref.id)
    end)
    :totable()

  -- Clear any tool's schemas
  local schemas_to_keep = {}
  local tools_in_use_to_keep = {}
  for id, schema in pairs(self.tools.schemas) do
    if not vim.tbl_contains(to_remove, id) then
      schemas_to_keep[id] = schema
      local tool_name = id:match("<tool>(.*)</tool>")
      if tool_name and self.tools.in_use[tool_name] then
        tools_in_use_to_keep[tool_name] = true
      end
    else
      log:debug("Removing tool schema and usage flag for ID: %s", id) -- Optional logging
    end
  end
  self.tools.schemas = schemas_to_keep
  self.tools.in_use = tools_in_use_to_keep
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
  self.status = CONSTANTS.STATUS_CANCELLING
  util.fire("ChatStopped", { bufnr = self.bufnr, id = self.id })

  if self.current_tool then
    job = self.current_tool
    self.current_tool = nil

    _G.codecompanion_cancel_tool = true
    pcall(function()
      job:shutdown()
    end)
  end

  if self.current_request then
    job = self.current_request
    self.current_request = nil
    if job then
      pcall(function()
        job:shutdown()
      end)
    end
    self.adapter.handlers.on_exit(self.adapter)
  end

  self.subscribers:stop()

  vim.schedule(function()
    log:debug("Chat request cancelled")
    self:done()
  end)
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
  pcall(api.nvim_buf_delete, self.bufnr, { force = true })
  if self.aug then
    api.nvim_clear_autocmds({ group = self.aug })
  end
  if self.ui.aug then
    api.nvim_clear_autocmds({ group = self.ui.aug })
  end
  util.fire("ChatClosed", { bufnr = self.bufnr, id = self.id })
  util.fire("ChatAdapter", { bufnr = self.bufnr, id = self.id, adapter = nil })
  util.fire("ChatModel", { bufnr = self.bufnr, id = self.id, model = nil })
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
  return ts_parse_codeblock(self, cursor)
end

---Clear the chat buffer
---@return nil
function Chat:clear()
  self.cycle = 1
  self.header_line = 1
  self.messages = {}
  self.refs = {}

  self.tools:clear()

  log:trace("Clearing chat buffer")
  self.ui:render(self.context, self.messages, self.opts):set_intro_msg()
  self:add_system_prompt()
  util.fire("ChatCleared", { bufnr = self.bufnr, id = self.id })
end

---Display the chat buffer's settings and messages
function Chat:debug()
  if vim.tbl_isempty(self.messages) then
    return
  end

  return ts_parse_settings(self.bufnr, self.yaml_parser, self.adapter), self.messages
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
