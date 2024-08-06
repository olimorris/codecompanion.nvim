local client = require("codecompanion.client")
local config = require("codecompanion").config
local keymaps = require("codecompanion.utils.keymaps")
local schema = require("codecompanion.schema")

local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils.util")
local yaml = require("codecompanion.utils.yaml")

local api = vim.api

local CONSTANTS = {
  NS_HEADER = "CodeCompanion-headers",
  NS_INTRO = "CodeCompanion-intro_message",
  NS_VIRTUAL_TEXT = "CodeCompanion-virtual_text",

  AUTOCMD_GROUP = "codecompanion.chat",
  AUTOCMD_USER_EVENT = "CodeCompanionChat",

  STATUS_ERROR = "error",
  STATUS_SUCCESS = "success",
  STATUS_FINISHED = "finished",

  SYSTEM_ROLE = "system",

  BLANK_DESC = "[No messages]",
}

local chat_query = [[
(
  atx_heading
  (atx_h2_marker)
  heading_content: (_) @role
)
(
  section
  [(paragraph) (fenced_code_block) (list)] @content
)
]]

local tool_query = [[
(
 (section
  (fenced_code_block
    (info_string) @lang
    (code_fence_content) @tool
  ) (#match? @lang "xml"))
)
]]

local llm_role = config.strategies.chat.roles.llm
local user_role = config.strategies.chat.roles.user

---@param bufnr integer
---@return nil
local function lock_buf(bufnr)
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = false
end

---@param bufnr integer
---@return nil
local function unlock_buf(bufnr)
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = true
end

---@param adapter? CodeCompanion.Adapter|string|function
---@return CodeCompanion.Adapter
local function resolve_adapter(adapter)
  adapter = adapter or config.adapters[config.strategies.chat.adapter]

  if type(adapter) == "string" then
    return require("codecompanion.adapters").use(adapter)
  elseif type(adapter) == "function" then
    return adapter()
  end

  return adapter
end

local _cached_settings = {}
---@param bufnr integer
---@param adapter? CodeCompanion.Adapter
---@param ts_query? string
---@return table
local function parse_settings(bufnr, adapter, ts_query)
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

  ts_query = ts_query or [[
    ((block_mapping (_)) @block)
  ]]

  local settings = {}
  local parser = vim.treesitter.get_parser(bufnr, "yaml", { ignore_injections = false })
  local query = vim.treesitter.query.parse("yaml", ts_query)
  local root = parser:parse()[1]:root()

  for _, match in query:iter_matches(root, bufnr) do
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
    elseif match[captures.content] then
      local content = vim.trim(vim.treesitter.get_node_text(match[captures.content], bufnr))
      if message.content then
        message.content = message.content .. "\n\n" .. content
      else
        message.content = content
      end
      if not message.role then
        message.role = user_role
      end
    end
  end

  if not vim.tbl_isempty(message) then
    table.insert(output, message)
  end

  return output
end

---@class CodeCompanion.Chat
---@return CodeCompanion.ToolExecuteResult|nil
local function parse_tool_schema(chat)
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
    if name == "tool" then
      local tool = vim.treesitter.get_node_text(node, response)
      table.insert(tools, tool)
    end
  end

  log:debug("Tool detected: %s", tools)

  --TODO: Parse XML to ensure the STag is <agent>

  if tools and #tools > 0 then
    return require("codecompanion.tools").run(chat, tools[#tools])
  end
end

---@type table<CodeCompanion.Chat>
local chatmap = {}

---@type CodeCompanion.Chat|nil
local last_chat = {}

local registered_cmp = false

---@class CodeCompanion.Chat
---@field opts CodeCompanion.ChatArgs Store all arguments in this table
---@field id integer The unique identifier for the chat
---@field header_ns integer The namespace for the virtual text that appears in the header
---@field adapter CodeCompanion.Adapter The adapter to use for the chat
---@field settings? table The settings that are used in the adapter of the chat buffer
---@field current_request table The current request being executed
---@field current_tool table The current tool being executed
---@field bufnr integer The buffer number of the chat
---@field context table The context of the buffer that the chat was initiated from
---@field intro_message? boolean Whether the welcome message has been shown
---@field saved_chat? string The name of the saved chat
---@field tokens? nil|number The number of tokens in the chat
---@field tools? CodeCompanion.Tools The tools available to the user
---@field tools_in_use? nil|table The tools that are currently being used in the chat
---@field variables? CodeCompanion.Variables The variables available to the user
---@field variable_output? nil|table The output after the variables have been executed
---@field hidden_msgs? table Place to store non-visible messages
local Chat = {}

---@class CodeCompanion.ChatArgs Arguments that can be injected into the chat
---@field context? table Context of the buffer that the chat was initiated from
---@field adapter? CodeCompanion.Adapter The adapter used in this chat buffer
---@field settings? table The settings that are used in the adapter of the chat buffer
---@field messages? table The messages to display in the chat buffer
---@field auto_submit? boolean Automatically submit the chat when the chat buffer is created
---@field stop_context_insertion? boolean Stop any visual selection from being automatically inserted into the chat buffer
---@field tokens? table Total tokens spent in the chat buffer so far
---@field saved_chat? string Name of the saved chat the chat buffer is aligned to
---@field status? string The status of any running jobs in the chat buffe
---@field last_role? string The role of the last response in the chat buffer

---@param args CodeCompanion.ChatArgs
function Chat.new(args)
  local id = math.random(10000000)
  log:trace("Chat created with ID %d", id)

  local self = setmetatable({
    opts = args,
    id = id,
    context = args.context,
    header_ns = api.nvim_create_namespace(CONSTANTS.NS_HEADER),
    saved_chat = args.saved_chat,
    tokens = args.tokens,
    status = "",
    last_role = user_role,
    tools = require("codecompanion.strategies.chat.tools").new(),
    tools_in_use = {},
    variables = require("codecompanion.strategies.chat.variables").new(),
    variable_output = {},
    hidden_msgs = {},
    create_buf = function()
      local bufnr = api.nvim_create_buf(false, true)
      api.nvim_buf_set_name(bufnr, string.format("[CodeCompanion] %d", id))
      api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
      api.nvim_buf_set_option(bufnr, "filetype", "codecompanion")

      return bufnr
    end,
  }, { __index = Chat })

  self.bufnr = self.create_buf()
  table.insert(chatmap, {
    name = "Chat " .. #chatmap + 1,
    description = CONSTANTS.BLANK_DESC,
    strategy = "chat",
    chat = self,
  })

  self.adapter = resolve_adapter(self.opts.adapter)
  if not self.adapter then
    return log:error("No adapter found")
  end
  self.settings = self.opts.settings or schema.get_default(self.adapter.args.schema, self.opts.settings)

  log:trace("Adapter: %s", self.adapter)

  self.close_last_chat()
  self:open():render(self.opts.messages):set_extmarks():set_autocmds()

  if self.opts.saved_chat then
    self:display_tokens()
  end
  if self.opts.auto_submit then
    self:submit()
  end

  last_chat = self
  return self
end

---Open/create the chat window
function Chat:open()
  if self:is_visible() then
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
    self.winnr = api.nvim_open_win(self.bufnr, true, win_opts)
  elseif window.layout == "vertical" then
    local cmd = "vsplit"
    if width ~= 0 then
      cmd = width .. cmd
    end
    vim.cmd(cmd)
    self.winnr = api.nvim_get_current_win()
    api.nvim_win_set_buf(self.winnr, self.bufnr)
  elseif window.layout == "horizontal" then
    local cmd = "split"
    if height ~= 0 then
      cmd = height .. cmd
    end
    vim.cmd(cmd)
    self.winnr = api.nvim_get_current_win()
    api.nvim_win_set_buf(self.winnr, self.bufnr)
  else
    self.winnr = api.nvim_get_current_win()
    api.nvim_set_current_buf(self.bufnr)
  end

  ui.set_win_options(self.winnr, window.opts)
  vim.bo[self.bufnr].textwidth = 0
  ui.buf_scroll_to_end(self.bufnr)
  keymaps.set(config.strategies.chat.keymaps, self.bufnr, self)

  log:trace("Chat opened with ID %d", self.id)

  return self
end

---Render the settings and any messages in the chat buffer
---@param messages? table
---@return self
function Chat:render(messages)
  local lines = {}
  local last_role = user_role

  local function spacer()
    table.insert(lines, "")
  end

  local function set_header(role)
    table.insert(lines, string.format("## %s", role))
    spacer()
    spacer()
  end

  local function set_messages(msgs)
    for i, msg in ipairs(msgs) do
      -- Only write non-system prompts to the chat buffer
      if msg.role ~= CONSTANTS.SYSTEM_ROLE or (msg.opts and msg.opts.visible == true) then
        if i > 1 and last_role ~= msg.role then
          spacer()
        end

        set_header(msg.role)
        for _, text in ipairs(vim.split(msg.content, "\n", { plain = true, trimempty = true })) do
          table.insert(lines, text)
        end

        last_role = msg.role
      else
        -- To make sure that we don't lose the order of the system prompts,
        -- we use a priority system:
        --     1. Reserved for the plugin's default system prompt.
        --     2. Reserved for any prompts that support functionality in the chat buffer.
        --     3. Reserved for any other system prompts.
        table.insert(self.hidden_msgs, {
          priority = msg.priority or 3,
          role = CONSTANTS.SYSTEM_ROLE,
          tag = msg.tag or nil,
          content = msg.content,
        })
      end
    end
  end

  if config.display.chat.show_settings then
    log:trace("Showing chat settings")
    lines = { "---" }
    local keys = schema.get_ordered_keys(self.adapter.args.schema)
    for _, key in ipairs(keys) do
      table.insert(lines, string.format("%s: %s", key, yaml.encode(self.settings[key])))
    end
    table.insert(lines, "---")
    spacer()
  end

  if not messages or #messages == 0 then
    log:trace("Setting the header for the chat buffer")
    set_header(user_role)
  end

  if messages then
    log:trace("Setting the messages in the chat buffer")
    set_messages(messages)
  end

  -- If the user has visually selected some text, add that to the chat buffer
  if self.context and self.context.is_visual and not self.opts.stop_context_insertion then
    log:trace("Adding visual selection to chat buffer")
    spacer()
    table.insert(lines, "```" .. self.context.filetype)
    for _, line in ipairs(self.context.lines) do
      table.insert(lines, line)
    end
    table.insert(lines, "```")
  end

  -- Add the default system prompt
  if config.opts.system_prompt then
    table.insert(self.hidden_msgs, 1, {
      priority = 1,
      role = CONSTANTS.SYSTEM_ROLE,
      content = config.opts.system_prompt,
    })
  end

  unlock_buf(self.bufnr)
  api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
  self:render_headers()

  ui.buf_scroll_to_end(self.bufnr)

  return self
end

---Set the autocmds for the chat buffer
---@return nil
function Chat:set_autocmds()
  local aug = api.nvim_create_augroup(CONSTANTS.AUTOCMD_GROUP .. self.bufnr, {
    clear = false,
  })

  local bufnr = self.bufnr

  -- Setup completion
  api.nvim_create_autocmd("InsertEnter", {
    group = aug,
    buffer = bufnr,
    once = true,
    desc = "Setup the completion of helpers in the chat buffer",
    callback = function()
      local has_cmp, cmp = pcall(require, "cmp")
      if has_cmp then
        if not registered_cmp then
          registered_cmp = true
          cmp.register_source("codecompanion_helpers", require("cmp_codecompanion.helpers").new())
          cmp.register_source("codecompanion_models", require("cmp_codecompanion.models").new())
        end
        cmp.setup.buffer({
          enabled = true,
          sources = {
            { name = "codecompanion_helpers" },
            { name = "codecompanion_models" },
          },
        })
      end
    end,
  })

  if config.display.chat.show_settings then
    api.nvim_create_autocmd("CursorMoved", {
      group = aug,
      buffer = bufnr,
      desc = "Show settings information in the CodeCompanion chat buffer",
      callback = function()
        self:on_cursor_moved()
      end,
    })

    -- Validate the settings
    api.nvim_create_autocmd("InsertLeave", {
      group = aug,
      buffer = bufnr,
      desc = "Parse the settings in the CodeCompanion chat buffer for any errors",
      callback = function()
        local settings = parse_settings(bufnr, self.adapter, [[((stream (_)) @block)]])

        local errors = schema.validate(self.adapter.args.schema, settings)
        local node = settings.__ts_node

        local items = {}
        if errors and node then
          for child in node:iter_children() do
            assert(child:type() == "block_mapping_pair")
            local key = vim.treesitter.get_node_text(child:named_child(0), bufnr)
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
        vim.diagnostic.set(config.ERROR_NS, bufnr, items)
      end,
    })
  end

  api.nvim_create_autocmd("BufWriteCmd", {
    group = aug,
    buffer = bufnr,
    desc = "Submit the CodeCompanion chat buffer",
    callback = function()
      self:save_chat()
      self:submit()
    end,
  })

  api.nvim_create_autocmd("InsertEnter", {
    group = aug,
    buffer = bufnr,
    once = true,
    desc = "Clear the virtual text in the CodeCompanion chat buffer",
    callback = function()
      local ns_id = api.nvim_create_namespace(CONSTANTS.NS_VIRTUAL_TEXT)
      api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    end,
  })

  api.nvim_create_autocmd("BufEnter", {
    group = aug,
    buffer = bufnr,
    desc = "Record the most recent chat",
    callback = function()
      last_chat = self
    end,
  })
end

---Set any extmarks in the chat buffer
---@return CodeCompanion.Chat|nil
function Chat:set_extmarks()
  if self.intro_message or (self.opts.messages and #self.opts.messages > 0) then
    return self
  end

  -- Welcome message
  local ns_intro = api.nvim_create_namespace(CONSTANTS.NS_INTRO)
  local id = api.nvim_buf_set_extmark(self.bufnr, ns_intro, api.nvim_buf_line_count(self.bufnr) - 1, 0, {
    virt_text = { { config.display.chat.intro_message, "CodeCompanionVirtualText" } },
    virt_text_pos = "eol",
  })
  api.nvim_create_autocmd("InsertEnter", {
    buffer = self.bufnr,
    callback = function()
      api.nvim_buf_del_extmark(self.bufnr, ns_intro, id)
    end,
  })
  self.intro_message = true

  return self
end

---Render the headers in the chat buffer and apply extmarks and separators
---@return nil
function Chat:render_headers()
  local separator = config.display.chat.messages_separator
  local lines = api.nvim_buf_get_lines(self.bufnr, 0, -1, false)

  for l, line in ipairs(lines) do
    if line:match("## " .. user_role .. "$") or line:match("## " .. llm_role .. "$") then
      local sep = vim.fn.strwidth(line) + 1

      if config.display.chat.show_separator then
        api.nvim_buf_set_extmark(self.bufnr, self.header_ns, l - 1, sep, {
          virt_text_win_col = sep,
          virt_text = { { string.rep(separator, vim.go.columns), "CodeCompanionChatSeparator" } },
          priority = 100,
          strict = false,
        })
      end

      -- Set the highlight group for the header
      api.nvim_buf_set_extmark(self.bufnr, self.header_ns, l - 1, 0, {
        end_col = sep + 1,
        hl_group = "CodeCompanionChatHeader",
        priority = 100,
        strict = false,
      })
    end
  end
  log:trace("Rendering headers in the chat buffer")
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

---Actions to take when the cursor moves in the chat buffer
---Used to show the LLM settings at the top of the buffer
---@return nil
function Chat:on_cursor_moved()
  local key_name, node = self:_get_settings_key()
  if not key_name or not node then
    vim.diagnostic.set(config.INFO_NS, self.bufnr, {})
    return
  end

  local key_schema = self.adapter.args.schema[key_name]
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
end

---Preprocess messages to handle tools, variables, and other components
---@param messages table
---@return table
function Chat:preprocess_messages(messages)
  local latest_msg = messages[#messages]

  -- Determine if we've already hidden a message
  local function is_hidden(msg)
    for _, hidden_msg in ipairs(self.hidden_msgs) do
      if hidden_msg.content == msg then
        return true
      end
    end
    return false
  end

  -- Store hidden messages in their own table
  local hide_msg = function(priority, content, role)
    if not is_hidden(content) then
      table.insert(self.hidden_msgs, {
        priority = priority,
        role = role or CONSTANTS.SYSTEM_ROLE,
        content = content,
      })
    end
  end

  -- Process multiple tools in a single message
  local tools = self.tools:parse(latest_msg.content)
  if tools then
    for tool, opts in pairs(tools) do
      latest_msg.content = self.tools:replace(latest_msg.content, tool)
      self.tools_in_use[tool] = opts
    end
  end

  -- Add the agent system prompt if tools are in use
  if util.count(self.tools_in_use) > 0 then
    hide_msg(2, config.strategies.agent.tools.opts.system_prompt, CONSTANTS.SYSTEM_ROLE)
    for _, opts in pairs(self.tools_in_use) do
      hide_msg(3, "\n\n" .. opts.system_prompt(opts.schema), CONSTANTS.SYSTEM_ROLE)
    end
  end

  -- Process variables
  local vars = self.variables:parse(self, messages[#messages].content, #messages)
  if vars then
    messages[#messages].content = self.variables:replace(messages[#messages].content, vars)
    table.insert(self.variable_output, vars)
  end

  -- Add variables to the message stack
  if self.variable_output then
    log:debug("Variables stored: %s", self.variable_output)
    for _, var in ipairs(self.variable_output) do
      table.insert(messages, var.index, {
        role = user_role,
        content = var.content,
      })
    end
    log:trace("Variable used in response: %s", self.variable_output)
  end

  -- TODO: Process slash commands here when implemented

  -- Insert the hidden messages back into the message stack in the correct order
  table.sort(self.hidden_msgs, function(a, b)
    return a.priority > b.priority
  end)
  for _, msg in ipairs(self.hidden_msgs) do
    table.insert(messages, 1, {
      role = msg.role,
      content = msg.content,
    })
  end

  return messages
end

---Submit the chat buffer's contents to the LLM
---@return nil
function Chat:submit()
  local bufnr = self.bufnr
  local settings, messages = parse_settings(bufnr, self.adapter), parse_messages(bufnr)
  if not messages or #messages == 0 or (not messages[#messages].content or messages[#messages].content == "") then
    log:warn("No messages to submit")
    return
  end

  messages = self:preprocess_messages(messages)

  log:debug("Settings: %s", settings)
  log:debug("Messages: %s", messages)

  -- log:trace("----- For Adapter test creation -----\nMessages: %s\n ---------- // END ----------", messages)
  -- log:trace("Settings: %s", settings)

  lock_buf(bufnr)
  log:info("Chat request started")

  self.current_request = client.new():stream(
    self.adapter:set_params(settings),
    self.adapter:map_roles(messages),
    function(err, data, done)
      if err then
        log:error("Error: %s", err)
        return self:reset()
      end

      -- With some adapters, the tokens come as part of the regular response so
      -- we need to account for that here before the client is terminated
      if data then
        self:get_tokens(data)
      end

      if done then
        self:append({ role = user_role, content = "" })
        self:display_tokens()
        self:save_chat()

        if self.status ~= CONSTANTS.STATUS_ERROR and util.count(self.tools_in_use) > 0 then
          parse_tool_schema(self)
        end

        api.nvim_exec_autocmds(
          "User",
          { pattern = CONSTANTS.AUTOCMD_USER_EVENT, data = { status = CONSTANTS.STATUS_FINISHED } }
        )

        log:info("Chat request completed")
        return self:reset()
      end

      if data then
        local result = self.adapter.args.callbacks.chat_output(data)

        if result and result.status == CONSTANTS.STATUS_SUCCESS then
          if result.output.role then
            result.output.role = llm_role
          end
          self:append(result.output)
        elseif result and result.status == CONSTANTS.STATUS_ERROR then
          self.status = CONSTANTS.STATUS_ERROR
          self:stop()
          log:error("Error: %s" .. result.output)
        end
      end
    end,
    function()
      self.current_request = nil
    end
  )
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
    job:shutdown()
  end
end

---Determine if the current chat buffer is active
---@return boolean
function Chat:is_active()
  return api.nvim_get_current_buf() == self.bufnr
end

---Hide the chat buffer from view
---@return nil
function Chat:hide()
  local layout = config.display.chat.window.layout

  if layout == "float" or layout == "vertical" or layout == "horizontal" then
    if self:is_active() then
      vim.cmd("hide")
    else
      api.nvim_win_hide(self.winnr)
    end
  else
    vim.cmd("buffer " .. vim.fn.bufnr("#"))
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

  local index = util.find_key(chatmap, "bufnr", self.bufnr)
  if index then
    table.remove(chatmap, index)
  end

  api.nvim_buf_delete(self.bufnr, { force = true })
  self = nil
end

---Determine if the chat buffer is visible
---@return boolean
function Chat:is_visible()
  return self.winnr and api.nvim_win_is_valid(self.winnr) and api.nvim_win_get_buf(self.winnr) == self.bufnr
end

---Get the last line, column and line count in the chat buffer
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
  local bufnr = self.bufnr

  if (data.role and data.role ~= self.last_role) or (opts and opts.force_role) then
    self.last_role = data.role
    table.insert(lines, "")
    table.insert(lines, "")
    table.insert(lines, string.format("## %s", data.role))
    table.insert(lines, "")
  end

  if data.content then
    for _, text in ipairs(vim.split(data.content, "\n", { plain = true, trimempty = false })) do
      table.insert(lines, text)
    end

    unlock_buf(bufnr)

    local last_line, last_column, line_count = self:last()
    if opts and opts.insert_at then
      last_line = opts.insert_at
      last_column = 0
    end

    local cursor_moved = api.nvim_win_get_cursor(0)[1] == line_count
    api.nvim_buf_set_text(bufnr, last_line, last_column, last_line, last_column, lines)
    self:render_headers()

    if self.last_role ~= user_role then
      lock_buf(bufnr)
    end

    if cursor_moved and self:is_active() then
      ui.buf_scroll_to_end(bufnr)
    elseif not self:is_active() then
      ui.buf_scroll_to_end(bufnr)
    end
  end
end

---Wrapper for appending a message to the chat buffer
---@param data table
---@param opts? table
---@return nil
function Chat:add_message(data, opts)
  self:append({ role = data.role, content = data.content }, opts)

  if opts and opts.notify then
    api.nvim_echo({
      { "[CodeCompanion.nvim]\n", "Normal" },
      { opts.notify, "MoreMsg" },
    }, true, {})
  end
end

---When a request has finished, reset the chat buffer
---@return nil
function Chat:reset()
  local bufnr = self.bufnr

  self.status = ""
  unlock_buf(bufnr)
end

---Get the messages from the chat buffer
---@return table
function Chat:get_messages()
  return parse_messages(self.bufnr)
end

---@param data table
---@return nil
function Chat:get_tokens(data)
  if self.adapter.args.features.tokens then
    local tokens = self.adapter.args.callbacks.tokens(data)
    if tokens then
      self.tokens = tokens
    end
  end
end

---Display the tokens in the chat buffer
function Chat:display_tokens()
  if config.display.chat.show_token_count and self.tokens then
    require("codecompanion.utils.tokens").display(self.tokens, self.bufnr)
  end
end

---Conceal parts of the chat buffer enclosed by a H2 heading
---@param heading string
---@return self
function Chat:conceal(heading)
  local parser = vim.treesitter.get_parser(self.bufnr, "markdown")

  local query = vim.treesitter.query.parse(
    "markdown",
    string.format(
      [[
    ((section
      ((atx_heading) @heading)
      (#eq? @heading "### %s")) @content)
  ]],
      heading
    )
  )
  local tree = parser:parse()[1]
  local root = tree:root()

  for _, captures, _ in query:iter_matches(root, self.bufnr, 0, -1, { all = true }) do
    if captures[2] then
      local node = captures[2]
      local start_row, _, end_row, _ = node[1]:range()

      if start_row < end_row then
        api.nvim_buf_set_option(self.bufnr, "foldmethod", "manual")
        api.nvim_buf_call(self.bufnr, function()
          vim.fn.setpos(".", { self.bufnr, start_row + 1, 0, 0 })
          vim.cmd("normal! zf" .. end_row .. "G")
        end)
        ui.buf_scroll_to_end(self.bufnr)
      end
    end
  end

  log:trace("Concealing %s", heading)
  return self
end

---CodeCompanion models completion source
---@param request table
---@param callback fun(request: table)
---@return nil
function Chat:complete(request, callback)
  local items = {}
  local cursor = api.nvim_win_get_cursor(0)
  local key_name, node = self:_get_settings_key({ pos = { cursor[1] - 1, 1 } })
  if not key_name or not node then
    callback({ items = items, isIncomplete = false })
    return
  end

  local key_schema = self.adapter.args.schema[key_name]
  if key_schema.type == "enum" then
    for _, choice in ipairs(key_schema.choices) do
      table.insert(items, {
        label = choice,
        kind = require("cmp").lsp.CompletionItemKind.Keyword,
      })
    end
  end

  callback({ items = items, isIncomplete = false })
end

---Clear the chat buffer
---@return nil
function Chat:clear()
  local function clear_ns(ns)
    for _, name in ipairs(ns) do
      local id = api.nvim_create_namespace(name)
      api.nvim_buf_clear_namespace(self.bufnr, id, 0, -1)
    end
  end

  local namespaces = {
    CONSTANTS.NS_INTRO,
    CONSTANTS.NS_VIRTUAL_TEXT,
    CONSTANTS.NS_HEADER,
  }

  self.tools_in_use = {}
  self.variable_output = {}
  self.hidden_msgs = {}
  self.opts.messages = nil
  self.tokens = nil
  clear_ns(namespaces)

  log:trace("Clearing chat buffer")
  self:render():set_extmarks()
end

---Saves the chat buffer if it has been loaded
---@return nil
function Chat:save_chat()
  if not self.saved_chat or not config.opts.auto_save_chats then
    return
  end

  local saved_chat = require("codecompanion.strategies.saved_chats")

  saved_chat = saved_chat.new({ filename = self.saved_chat })
  saved_chat:save(self)
  log:trace("Chat saved")
end

---Returns the chat object(s) based on the buffer number
---@param bufnr? integer
---@return CodeCompanion.Chat|table
function Chat.buf_get_chat(bufnr)
  if not bufnr then
    return chatmap
  end

  if bufnr == 0 then
    bufnr = api.nvim_get_current_buf()
  end
  return chatmap[util.find_key(chatmap, "bufnr", bufnr)].chat
end

---Returns the last chat that was visible
---@return CodeCompanion.Chat|nil
function Chat.last_chat()
  return last_chat or nil
end

---Close the last chat buffer
---@return nil
function Chat.close_last_chat()
  if last_chat and not util.is_empty(last_chat) and last_chat:is_visible() then
    last_chat:hide()
  end
end

return Chat
