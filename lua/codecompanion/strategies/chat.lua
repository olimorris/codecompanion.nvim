local Job = require("plenary.job")
local client = require("codecompanion.client")
local config = require("codecompanion").config
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local schema = require("codecompanion.schema")
local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils.util")
local yaml = require("codecompanion.utils.yaml")

local api = vim.api

local CONSTANTS = {
  NS_INTRO_MESSAGE = "CodeCompanion-intro_message",
  NS_VIRTUAL_TEXT = "CodeCompanion-virtual_text",

  AUTOCMD_CHAT = "CodeCompanionChat",

  STATUS_ERROR = "error",
  STATUS_SUCCESS = "success",
  STATUS_FINISHED = "finished",
}

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

local agent_query = [[
(
 (section
  (fenced_code_block
    (info_string) @lang
    (code_fence_content) @agents
  ) (#match? @lang "xml"))
)
]]

---@param adapter? CodeCompanion.Adapter|string
---@return CodeCompanion.Adapter
local function resolve_adapter(adapter)
  adapter = adapter or config.adapters[config.strategies.chat.adapter]

  if type(adapter) == "string" then
    return require("codecompanion.adapters").use(adapter)
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

---Parse the buffer for any keywords as defined in the config
---@param chat CodeCompanion.Chat
---@param messages table
---@return nil
local function parse_helpers(chat, messages)
  if not config.opts.send_code then
    return
  end

  local chat_maps = require("codecompanion.helpers.chat")

  ---@param rhs string|table|fun(self)
  ---@return table|nil
  local function resolve(rhs)
    if type(rhs) == "string" and vim.startswith(rhs, "helpers.chat.") then
      -- The last part of the string is the function to call
      local splits = vim.split(rhs, ".", { plain = true })
      return resolve(chat_maps[splits[#splits]])
    else
      return rhs(chat)
    end
  end

  ---@param message string
  ---@param helpers table
  ---@return string|nil
  local function find(message, helpers)
    for helper, _ in pairs(helpers) do
      if message:match("%f[%w@]" .. "@" .. helper .. "%f[%W]") then
        return helper
      end
    end
    return nil
  end

  -- Only parse the last message
  local message = messages[#messages]
  local helper = find(message.content, config.strategies.chat.helpers)
  if helper then
    local content = resolve(config.strategies.chat.helpers[helper].callback)

    if content then
      log:debug("Parsed helper in chat buffer at message index %d", #messages)
      log:trace("parse_helper content: %s", content)
      chat.buffers = {
        index = #messages,
        content = content,
      }
    end
  end
end

---@param chat CodeCompanion.Chat
local function parse_agents(chat)
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
  local query = vim.treesitter.query.parse("markdown", agent_query)

  local agent_xmls = {}
  for id, node in query:iter_captures(tree:root(), response, 0, -1) do
    local name = query.captures[id]
    if name == "agents" then
      local agent = vim.treesitter.get_node_text(node, response)
      table.insert(agent_xmls, agent)
    end
  end

  log:debug("Agents detected: %s", agent_xmls)
  log:debug("Agents num: %s", #agent_xmls)

  --TODO: Parse XML to ensure the STag is <agent>

  -- execute all agent
  if agent_xmls and #agent_xmls > 0 then
    for i, agent_xml in ipairs(agent_xmls) do
      if chat.current_agent then
        log:info("Command Runner: There is an agent running, waiting for it to finish")
        -- if there is an job agent running, we should wait for it to finish
        chat.current_agent:join()
        -- when current_agent is done the last on_exit method may be called later, so we need to wait for it to finish
        vim.wait(1000, function()
          return not vim.g.codecompanion_agent_running
        end)
        log:info("Command Runner: Agent finished running")
      end

      -- after last agent is done, we need to set the current_agent to nil
      chat.current_agent = nil

      log:info("agent run: %s", agent_xml)
      -- NOTE: when the last agent is executed, the last_agent flag is set to true make sure the chat:submit() is called after the last agent is executed
      require("codecompanion.agents").run(chat, agent_xml, { last_agent = i == #agent_xmls })
    end
  end
end

---@type table<integer, CodeCompanion.Chat>
local chatmap = {}

---@type table<CodeCompanion.Chat>
_G.codecompanion_chats = {}

---@class chat CodeCompanion.Chat
local function set_welcome_message(chat)
  if chat.intro_message then
    return
  end

  local ns_id = api.nvim_create_namespace(CONSTANTS.NS_INTRO_MESSAGE)

  local id = api.nvim_buf_set_extmark(chat.bufnr, ns_id, api.nvim_buf_line_count(chat.bufnr) - 1, 0, {
    virt_text = { { config.display.chat.intro_message, "CodeCompanionVirtualText" } },
    virt_text_pos = "eol",
  })

  api.nvim_create_autocmd("InsertEnter", {
    buffer = chat.bufnr,
    callback = function()
      api.nvim_buf_del_extmark(chat.bufnr, ns_id, id)
    end,
  })

  chat.intro_message = true
end

---@class CodeCompanion.Chat
---@field id integer
---@field adapter CodeCompanion.Adapter
---@field current_request table
---@field current_agent Job
---@field bufnr integer
---@field opts CodeCompanion.ChatArgs
---@field context table
---@field saved_chat? string
---@field buffers? nil|table
---@field tokens? nil|number
---@field settings table
---@field type string
local Chat = {}

---@class CodeCompanion.ChatArgs
---@field context? table
---@field adapter? CodeCompanion.Adapter
---@field messages? table
---@field auto_submit? boolean
---@field stop_context_insertion? boolean
---@field settings? table
---@field tokens? table
---@field type? string
---@field saved_chat? string
---@field status?string
---@field last_role? string

---@param args CodeCompanion.ChatArgs
function Chat.new(args)
  local id = math.random(10000000)

  local self = setmetatable({
    id = id,
    context = args.context,
    saved_chat = args.saved_chat,
    tokens = args.tokens,
    opts = args,
    status = "",
    last_role = "user",
    create_buf = function()
      local bufnr = api.nvim_create_buf(false, true)
      api.nvim_buf_set_name(bufnr, string.format("[CodeCompanion] %d", id))
      api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
      api.nvim_buf_set_option(bufnr, "filetype", "codecompanion")
      api.nvim_buf_set_option(bufnr, "syntax", "markdown")
      vim.b[bufnr].codecompanion_type = "chat"

      return bufnr
    end,
  }, { __index = Chat })

  self.bufnr = self.create_buf()
  chatmap[self.bufnr] = self
  self:open()

  self.adapter = resolve_adapter(args.adapter)
  if not self.adapter then
    vim.notify("[CodeCompanion.nvim]\nNo adapter found", vim.log.levels.ERROR)
    return
  end

  self.settings = args.settings or schema.get_default(self.adapter.args.schema, args.settings)

  self:render(args.messages or {}):set_autocmds()

  if not args.messages or #args.messages == 0 then
    set_welcome_message(self)
  end
  if args.saved_chat then
    self:display_tokens()
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
end

---Render the chat buffer
---@param messages table
---@return self
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

  -- Add any messages to the buffer
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

  -- and if the user has visually selected some text, add that
  if self.context and self.context.is_visual and not self.opts.stop_context_insertion then
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

  ui.buf_scroll_to_end(self.bufnr)

  return self
end

---Set the autocmds for the chat buffer
---@return nil
function Chat:set_autocmds()
  local aug = api.nvim_create_augroup("CodeCompanion_" .. self.bufnr, {
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
        require("cmp").register_source("codecompanion_helpers", require("cmp_codecompanion.helpers").new())
        require("cmp").register_source("codecompanion_models", require("cmp_codecompanion.models").new())
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
    api.nvim_create_autocmd({ "CursorMoved" }, {
      group = aug,
      buffer = bufnr,
      desc = "Show settings information in the CodeCompanion chat buffer",
      callback = function()
        self:on_cursor_moved()
      end,
    })

    -- Validate the settings
    vim.api.nvim_create_autocmd("InsertLeave", {
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

  -- Submit the chat
  api.nvim_create_autocmd("BufWriteCmd", {
    group = aug,
    buffer = bufnr,
    desc = "Submit the CodeCompanion chat buffer",
    callback = function()
      -- make sure submit after current request is done or agent is done
      -- prevent two requests from being sent simultaneously and writing to the same buffer
      if not self.current_request or not self.current_agent then
        self:submit()
      end
    end,
  })

  -- Clear the virtual text when the user starts typing
  if util.count(_G.codecompanion_chats) == 0 then
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
  end

  -- Handle toggling the buffer and chat window
  api.nvim_create_autocmd("User", {
    desc = "Store the current chat buffer",
    group = aug,
    pattern = CONSTANTS.AUTOCMD_CHAT,
    callback = function(request)
      if request.data.bufnr ~= bufnr or request.data.action ~= "hide_buffer" then
        return
      end

      _G.codecompanion_last_chat_buffer = self

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
          chat = self,
        }
      end
    end,
  })
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

---Submit the chat buffer's contents to the LLM
---@return nil
function Chat:submit()
  local bufnr = self.bufnr
  local settings, messages = parse_settings(bufnr, self.adapter), parse_messages(bufnr)
  if not messages or #messages == 0 or (not messages[#messages].content or messages[#messages].content == "") then
    return
  end

  -- Add the adapter's chat prompt
  if config.opts.system_prompt then
    table.insert(messages, 1, {
      role = "system",
      content = config.opts.system_prompt,
    })
  end

  -- Add the contents of any buffers
  parse_helpers(self, messages)
  if self.buffers then
    table.insert(messages, self.buffers.index, {
      role = "user",
      content = self.buffers.content,
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

    -- Sometimes the token payload comes as part of the final response so we
    -- need to check for the tokens before the client is terminated
    if data then
      self:get_tokens(data)
    end

    if done then
      -- if find unclosed markdown code block close it
      if table.concat(api.nvim_buf_get_lines(self.bufnr, 0, -1, false), "\n"):match("```[^`]*$") then
        self:append({ role = "assistant", content = "\n```" })
      end

      self:append({ role = "user", content = "" })
      self:display_tokens()
      if self.status ~= CONSTANTS.STATUS_ERROR then
        -- after shutdown this parse_agents may be called multiple times
        pcall(parse_agents, self)
      end
      api.nvim_exec_autocmds(
        "User",
        { pattern = CONSTANTS.AUTOCMD_CHAT, data = { status = CONSTANTS.STATUS_FINISHED } }
      )
      return self:reset()
    end

    if data then
      local result = self.adapter.args.callbacks.chat_output(data)

      if result and result.status == CONSTANTS.STATUS_SUCCESS then
        self:append(result.output)
      elseif result and result.status == CONSTANTS.STATUS_ERROR then
        self.status = CONSTANTS.STATUS_ERROR
        self:stop()
        vim.notify("Error: " .. result.output, vim.log.levels.ERROR)
      end
    end
  end, function()
    self.current_request = nil
  end)
end

---Stop streaming the response from the LLM
---@return nil
function Chat:stop()
  local job
  if self.current_agent then
    job = self.current_agent
    self.current_agent = nil

    _G.codecompanion_cancel_agent = true
    job:shutdown()
  end
  if self.current_request then
    job = self.current_request
    self.current_request = nil
    job:shutdown()
  end
end

---Hide the chat buffer from view
---@return nil
function Chat:hide()
  local layout = config.display.chat.window.layout

  if layout == "float" or layout == "vertical" or layout == "horizontal" then
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
    { pattern = CONSTANTS.AUTOCMD_CHAT, data = { action = "hide_buffer", bufnr = self.bufnr } }
  )
end

---Close the current chat buffer
---@return nil
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
  opts = vim.tbl_extend("force", { force_role = false, update_last_role = true }, opts or {})

  if (data.role and data.role ~= self.last_role) or (opts and opts.force_role) then
    if opts.update_last_role then
      self.last_role = data.role
    end
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
  return self.winnr and api.nvim_win_is_valid(self.winnr) and api.nvim_win_get_buf(self.winnr) == self.bufnr
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
      (#eq? @heading "## %s")) @content)
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
        vim.api.nvim_buf_set_option(self.bufnr, "foldmethod", "manual")
        vim.api.nvim_buf_call(self.bufnr, function()
          vim.fn.setpos(".", { self.bufnr, start_row + 1, 0, 0 })
          vim.cmd("normal! zf" .. end_row .. "G")
        end)
        ui.buf_scroll_to_end(self.bufnr)
      end
    end
  end

  return self
end

---Determine if the current chat buffer is active
---@return boolean
function Chat:active()
  return api.nvim_get_current_buf() == self.bufnr
end

---CodeCompanion models completion source
---@param request table
---@param callback fun(request: table)
---@return nil
function Chat:complete(request, callback)
  local items = {}
  local cursor = vim.api.nvim_win_get_cursor(0)
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

---Returns the chat object based on the buffer number
---@param bufnr? integer
---@return nil|CodeCompanion.Chat
function Chat.buf_get_chat(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  return chatmap[bufnr]
end

return Chat
