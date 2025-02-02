local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local completion = require("codecompanion.completion")
local config = require("codecompanion.config")
local schema = require("codecompanion.schema")

local hash = require("codecompanion.utils.hash")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
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

---Make an id from a string or table
---@param val string|table
---@return number
local function make_id(val)
  return hash.hash(val)
end

local _cached_settings = {}
local _yaml_parser

---Parse the chat buffer for settings
---@param bufnr integer
---@param adapter? CodeCompanion.Adapter
---@return table
local function ts_parse_settings(bufnr, adapter)
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
  if not _yaml_parser then
    _yaml_parser = vim.treesitter.get_parser(bufnr, "yaml", { ignore_injections = false })
  end

  local query = get_query("yaml", "chat")
  local root = _yaml_parser:parse()[1]:root()

  local end_line = -1
  if adapter then
    -- Account for the two YAML lines and the fact Tree-sitter is 0-indexed
    end_line = vim.tbl_count(adapter:make_from_schema()) + 2 - 1
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
---@return { content: string }
local function ts_parse_messages(chat, start_range)
  local query = get_query("markdown", "chat")

  local tree = chat.parser:parse({ start_range - 1, -1 })[1]
  local root = tree:root()

  local content = {}
  local last_role = nil

  for id, node in query:iter_captures(root, chat.bufnr, start_range - 1, -1) do
    if query.captures[id] == "role" then
      last_role = get_node_text(node, chat.bufnr)
    elseif last_role == chat.ui:format_header(user_role) and query.captures[id] == "content" then
      table.insert(content, get_node_text(node, chat.bufnr))
    end
  end

  if not vim.tbl_isempty(content) then
    return { content = vim.trim(table.concat(content, "\n\n")) }
  end

  return { content = "" }
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
    cycle = 1,
    header_line = 1,
    from_prompt_library = args.from_prompt_library or false,
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

  local ok, parser = pcall(vim.treesitter.get_parser, self.bufnr, "markdown")
  if not ok then
    return log:error("Could not find the markdown Tree-sitter parser")
  end
  self.parser = parser

  self.references = require("codecompanion.strategies.chat.references").new({ chat = self })
  self.watchers = require("codecompanion.strategies.chat.watchers").new()
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
  util.fire("ChatCreated", { bufnr = self.bufnr, from_prompt_library = self.from_prompt_library })

  self:apply_settings(schema.get_default(self.adapter.schema, self.opts.settings))

  self.ui = require("codecompanion.strategies.chat.ui").new({
    adapter = self.adapter,
    id = self.id,
    bufnr = self.bufnr,
    roles = { user = user_role, llm = llm_role },
    settings = self.settings,
  })

  self.close_last_chat()
  self.ui:open():render(self.context, self.messages, self.opts):set_extmarks(self.opts)

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

  self:add_system_prompt():set_autocmds()

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

  api.nvim_create_autocmd("CompleteDone", {
    group = self.aug,
    buffer = bufnr,
    callback = function()
      local item = vim.v.completed_item
      if item.user_data and item.user_data.type == "slash_command" then
        -- Clear the word from the buffer
        local row, col = unpack(api.nvim_win_get_cursor(0))
        api.nvim_buf_set_text(bufnr, row - 1, col - #item.word, row - 1, col, { "" })

        completion.slash_commands_execute(item.user_data, self)
      end
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
        local settings = ts_parse_settings(bufnr, self.adapter)

        local errors = schema.validate(self.adapter.schema, settings, self.adapter)
        local node = settings.__ts_node

        local items = {}
        if errors and node then
          for child in node:iter_children() do
            assert(child:type() == "block_mapping_pair")
            local key = get_node_text(child:named_child(0), self.bufnr)
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
  local key_name = get_node_text(key_node, self.bufnr)
  return key_name, node
end

---Format and apply settings to the chat buffer
---@param settings? table
---@return self
function Chat:apply_settings(settings)
  self.settings = settings or schema.get_default(self.adapter.schema, self.opts.settings)
  _cached_settings[self.bufnr] = self.settings

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

---The source to provide the model entries for completion
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

---Determine if a tag exists in the messages table
---@param tag string
---@param messages table
---@return boolean
local function has_tag(tag, messages)
  return vim.tbl_contains(
    vim.tbl_map(function(msg)
      return msg.opts.tag
    end, messages),
    tag
  )
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
    self:add_message({
      role = config.constants.SYSTEM_ROLE,
      content = config.strategies.chat.agents.tools.opts.system_prompt,
    }, { visible = false, reference = "tool_system_prompt", tag = "tool" })
  end

  local id = "<tool>" .. tool .. "</tool>"
  self.references:add({
    source = "tool",
    name = "tool",
    id = id,
  })

  self.tools_in_use[tool] = true

  local resolved = self.tools.resolve(tool_config)
  if resolved then
    self:add_message(
      { role = config.constants.SYSTEM_ROLE, content = resolved.system_prompt(resolved.schema) },
      { visible = false, tag = "tool", reference = id }
    )
  end

  util.fire("ChatToolAdded", { bufnr = self.bufnr, tool = tool })

  return self
end

---Add a message to the message table
---@param data { role: string, content: string }
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
  log:time()
  opts = opts or {}

  local bufnr = self.bufnr

  local message = ts_parse_messages(self, self.header_line)

  -- Check if any watched buffers have changes
  self.watchers:check_for_changes(self)

  if not self:has_user_messages(message) then
    return log:info("No messages to submit")
  end

  --- Only send the user's last message if we're not regenerating the response
  if not opts.regenerate and not vim.tbl_isempty(message) and message.content ~= "" then
    self:add_message({ role = config.constants.USER_ROLE, content = message.content })
  end
  message = self.references:clear(self.messages[#self.messages])

  self:apply_tools_and_variables(message)
  self:check_references()
  self:add_pins()

  -- Check if the user has manually overridden the adapter
  if vim.g.codecompanion_adapter and self.adapter.name ~= vim.g.codecompanion_adapter then
    self.adapter = adapters.resolve(config.adapters[vim.g.codecompanion_adapter])
  end

  local settings = ts_parse_settings(bufnr, self.adapter)
  settings = self.adapter:map_schema_to_params(settings)

  log:debug("Settings:\n%s", settings)
  log:debug("Messages:\n%s", self.messages)
  log:info("Chat request started")

  self.ui:lock_buf()

  self:set_range(2) -- this accounts for the LLM header
  local output = {}
  log:info("ELAPSED TIME: %s", log:time())
  self.current_request = client
    .new({ adapter = settings })
    :request(self.adapter:map_roles(vim.deepcopy(self.messages)), {
      ---@param err { message: string, stderr: string }
      ---@param data table
      callback = function(err, data)
        if err and err.stderr ~= "{}" then
          self.status = CONSTANTS.STATUS_ERROR
          log:error("Error: %s", err.stderr)
          return self:done(output)
        end

        if data then
          if self.adapter.features.tokens then
            local tokens = self.adapter.handlers.tokens(self.adapter, data)
            if tokens then
              self.ui.tokens = tokens
            end
          end

          local result = self.adapter.handlers.chat_output(self.adapter, data)
          if result and result.status == CONSTANTS.STATUS_SUCCESS then
            if result.output.role then
              result.output.role = config.constants.LLM_ROLE
            end
            self.status = CONSTANTS.STATUS_SUCCESS
            table.insert(output, result.output.content)
            self:add_buf_message(result.output)
          end
        end
      end,
      done = function()
        self:done(output)
      end,
    }, {
      bufnr = bufnr,
      strategy = "chat",
    })
end

---Increment the cycle count in the chat buffer
---@return nil
function Chat:increment_cycle()
  self.cycle = self.cycle + 1
end

---Set the last edited range in the chat buffer
---@param modifier? number
---@return nil
function Chat:set_range(modifier)
  modifier = modifier or 0
  self.header_line = api.nvim_buf_line_count(self.bufnr) + modifier
end

---Method to call after the response from the LLM is received
---@param output table The output from the LLM
---@return nil
function Chat:done(output)
  self.current_request = nil
  if self.status == CONSTANTS.STATUS_CANCELLING then
    self.status = ""
    return self:reset()
  end

  if not vim.tbl_isempty(output) then
    self:add_message({
      role = config.constants.LLM_ROLE,
      content = vim.trim(table.concat(output, "")),
    })
  end

  self:increment_cycle()
  self:add_buf_message({ role = config.constants.USER_ROLE, content = "" })

  local assistant_range = self.header_line
  self:set_range(-2)
  self.ui:display_tokens(self.parser, self.header_line)
  self.references:render()

  if self.status == CONSTANTS.STATUS_SUCCESS and self:has_tools() then
    self.tools:parse_buffer(self, assistant_range, self.header_line - 1)
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
      if subscriber.order and subscriber.order < self.cycle then
        action_subscription(subscriber)
      elseif not subscriber.order then
        action_subscription(subscriber)
      end
    end)
  end
end

---Reconcile the references table to the references in the chat buffer
---@return nil
function Chat:check_references()
  local refs = self.references:get_from_chat()
  if vim.tbl_isempty(refs) and vim.tbl_isempty(self.refs) then
    return
  end

  -- Fetch references that exist on the chat object but not in the buffer
  local to_remove = vim
    .iter(self.refs)
    :filter(function(ref)
      return not vim.tbl_contains(refs, ref.id)
    end)
    :map(function(ref)
      return ref.id
    end)
    :totable()

  if vim.tbl_isempty(to_remove) then
    return
  end

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
end

---Add updated content from the pins to the chat buffer
---@return nil
function Chat:add_pins()
  local pins = vim
    .iter(self.refs)
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
    vim.iter(self.messages):each(function(msg)
      if msg.opts and msg.opts.reference == pin.id and msg.cycle == self.cycle then
        exists = true
      end
    end)
    if not exists then
      util.fire("ChatPin", { bufnr = self.bufnr, id = pin.id })
      require(pin.source)
        .new({ Chat = self })
        :output({ path = pin.path, bufnr = pin.bufnr, params = pin.params }, { pin = true })
    end
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
  self.status = CONSTANTS.STATUS_CANCELLING
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
  if self.aug then
    api.nvim_clear_autocmds({ group = self.aug })
  end
  if self.ui.aug then
    api.nvim_clear_autocmds({ group = self.ui.aug })
  end
  util.fire("ChatClosed", { bufnr = self.bufnr })
  util.fire("ChatAdapter", { bufnr = self.bufnr, adapter = nil })
  util.fire("ChatModel", { bufnr = self.bufnr, model = nil })
  self = nil
end

local has_been_reasoning = false

---Add a message directly to the chat buffer. This will be visible to the user
---@param data table
---@param opts? table
function Chat:add_buf_message(data, opts)
  local lines = {}
  local bufnr = self.bufnr
  local new_response = false

  local function write(text)
    for _, t in ipairs(vim.split(text, "\n", { plain = true, trimempty = false })) do
      table.insert(lines, t)
    end
  end

  local function new_role()
    new_response = true
    self.last_role = data.role
    table.insert(lines, "")
    table.insert(lines, "")
    self.ui:set_header(lines, config.strategies.chat.roles[data.role])
  end

  local function append_data()
    if data.reasoning then
      has_been_reasoning = true
      if new_response then
        table.insert(lines, "### Reasoning")
        table.insert(lines, "")
      end
      write(data.reasoning)
    else
      if has_been_reasoning then
        has_been_reasoning = false
        table.insert(lines, "")
        table.insert(lines, "")
        table.insert(lines, "### Response")
        table.insert(lines, "")
      end
      write(data.content)
    end
  end

  local function update_buffer()
    self.ui:unlock_buf()
    local last_line, last_column, line_count = self.ui:last()
    if opts and opts.insert_at then
      last_line = opts.insert_at
      last_column = 0
    end

    local cursor_moved = api.nvim_win_get_cursor(0)[1] == line_count
    api.nvim_buf_set_text(bufnr, last_line, last_column, last_line, last_column, lines)

    if new_response then
      self.ui:render_headers()
    end

    if self.last_role ~= config.constants.USER_ROLE then
      self.ui:lock_buf()
    end

    if cursor_moved and self.ui:is_active() then
      self.ui:follow()
    elseif not self.ui:is_active() then
      self.ui:follow()
    end
  end

  -- Handle a new role
  if (data.role and data.role ~= self.last_role) or (opts and opts.force_role) then
    new_role()
  end

  -- Append the output from the LLM
  if data.content or data.reasoning then
    append_data()
    update_buffer()
  end
end

---When a request has finished, reset the chat buffer
---@return nil
function Chat:reset()
  self.status = ""
  self.ui:unlock_buf()
end

---Get the messages from the chat buffer
---@return table
function Chat:get_messages()
  return self.messages
end

---Subscribe to a chat buffer
---@param event { name: string, type: string, callback: fun() }
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
  return self.ui:fold_code()
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
  self.tools_in_use = {}

  log:trace("Clearing chat buffer")
  self.ui:render(self.context, self.messages, self.opts):set_extmarks(self.opts)
  self:add_system_prompt()
end

---Display the chat buffer's settings and messages
function Chat:debug()
  if vim.tbl_isempty(self.messages) then
    return
  end

  return ts_parse_settings(self.bufnr, self.adapter), self.messages
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
    if last_chat.ui:is_visible() then
      last_chat.ui:hide()
    end
  end
end

return Chat
