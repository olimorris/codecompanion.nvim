local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local schema = require("codecompanion.schema")
local util = require("codecompanion.utils.util")
local yaml = require("codecompanion.utils.yaml")

local api = vim.api

local yaml_query = [[
(block_mapping_pair
  key: (_) @key
  value: (_) @value)
]]

local chat_query = [[
(atx_heading
  (atx_h1_marker)
  heading_content: (_) @role
  )

(section
  [(paragraph) (fenced_code_block) (list)] @text
  )
]]

local config_settings = {}
---@param bufnr integer
---@return table
local function parse_settings(bufnr)
  if config_settings[bufnr] then
    return config_settings[bufnr]
  end

  if not config.options.display.chat.show_settings then
    config_settings[bufnr] = vim.deepcopy(config.options.ai_settings)
    config_settings[bufnr].model = config_settings[bufnr].models.chat
    config_settings[bufnr].models = nil

    log:trace("Using the settings from the user's config: %s", config_settings[bufnr])
    return config_settings[bufnr]
  end

  local settings = {}
  local parser = vim.treesitter.get_parser(bufnr, "yaml")

  local query = vim.treesitter.query.parse("yaml", yaml_query)
  local root = parser:parse()[1]:root()
  pcall(vim.tbl_add_reverse_lookup, query.captures)

  for _, match in query:iter_matches(root, bufnr) do
    local key = vim.treesitter.get_node_text(match[query.captures.key], bufnr)
    local value = vim.treesitter.get_node_text(match[query.captures.value], bufnr)
    settings[key] = yaml.decode(value)
  end

  return settings or {}
end

---@param bufnr integer
---@return table
---@return CodeCompanion.ChatMessage[]
local function parse_messages_buffer(bufnr)
  local ret = {}

  local parser = vim.treesitter.get_parser(bufnr, "markdown")
  local query = vim.treesitter.query.parse("markdown", chat_query)
  local root = parser:parse()[1]:root()
  pcall(vim.tbl_add_reverse_lookup, query.captures)
  local message = {}
  for _, match in query:iter_matches(root, bufnr) do
    if match[query.captures.role] then
      if not vim.tbl_isempty(message) then
        table.insert(ret, message)
        message = { role = "", content = "" }
      end
      message.role = vim.trim(vim.treesitter.get_node_text(match[query.captures.role], bufnr):lower())
    elseif match[query.captures.text] then
      local text = vim.trim(vim.treesitter.get_node_text(match[query.captures.text], bufnr))
      if message.content then
        message.content = message.content .. "\n\n" .. text
      else
        message.content = text
      end
      -- If there's no role because they just started typing in a blank file, assign the user role
      if not message.role then
        message.role = "user"
      end
    end
  end

  if not vim.tbl_isempty(message) then
    table.insert(ret, message)
  end

  return parse_settings(bufnr), ret
end

---@param bufnr integer
---@param settings CodeCompanion.ChatSettings
---@param messages CodeCompanion.ChatMessage[]
---@param context table
local function render_messages(bufnr, settings, messages, context)
  local lines = {}
  if config.options.display.chat.show_settings then
    -- Put the settings at the top of the buffer
    lines = { "---" }
    local keys = schema.get_ordered_keys(schema.static.chat_settings)
    for _, key in ipairs(keys) do
      table.insert(lines, string.format("%s: %s", key, yaml.encode(settings[key])))
    end

    table.insert(lines, "---")
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

  if context and context.is_visual then
    table.insert(lines, "")
    table.insert(lines, "```" .. context.filetype)
    for _, line in ipairs(context.lines) do
      table.insert(lines, line)
    end
    table.insert(lines, "```")
  end

  local modifiable = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true
  api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = modifiable
end

local display_tokens = function(bufnr)
  if config.options.show_token_count then
    require("codecompanion.utils.tokens").display_tokens(bufnr)
  end
end

---@param bufnr number
---@param conversation CodeCompanion.Conversation
local function create_conversation_autocmds(bufnr, conversation)
  if config.options.conversations.auto_save then
    local group = api.nvim_create_augroup("CodeCompanionConversations", {})

    local function save()
      vim.schedule(function()
        conversation:save(bufnr, parse_messages_buffer(bufnr))
      end)
    end

    api.nvim_create_autocmd("InsertLeave", {
      buffer = bufnr,
      group = group,
      callback = function()
        log:trace("Conversation automatically saved")
        save()
      end,
    })
    api.nvim_create_autocmd({ "User" }, {
      group = group,
      pattern = "CodeCompanion",
      callback = function(request)
        if request.buf == bufnr and request.data.status == "finished" then
          log:trace("Conversation automatically saved")
          save()
        end
      end,
    })
  end
end

---@param bufnr number
local function create_conversation_commands(bufnr)
  local conversation = require("codecompanion.strategy.conversation").new({})

  api.nvim_buf_create_user_command(bufnr, "CodeCompanionConversationSaveAs", function()
    vim.ui.input({ prompt = "Conversation Name" }, function(filename)
      if not filename then
        return
      end
      conversation.filename = filename
      conversation:save(bufnr, parse_messages_buffer(bufnr))
      create_conversation_autocmds(bufnr, conversation)
    end)
  end, { desc = "Save the conversation" })

  -- Create manual save
end

---@type table<integer, CodeCompanion.Chat>
local chatmap = {}

local cursor_moved_autocmd
local function watch_cursor()
  if cursor_moved_autocmd then
    return
  end
  cursor_moved_autocmd = api.nvim_create_autocmd({ "CursorMoved", "BufEnter" }, {
    desc = "Show line information in a Code Companion buffer",
    callback = function(args)
      local chat = chatmap[args.buf]
      if chat then
        if api.nvim_win_get_buf(0) == args.buf then
          chat:on_cursor_moved()
        end
      end
    end,
  })
end

_G.codecompanion_chats = {}

local registered_cmp = false

---@param bufnr number
---@param args table
local function chat_autocmds(bufnr, args)
  -- Submit the chat
  api.nvim_create_autocmd("BufWriteCmd", {
    buffer = bufnr,
    callback = function()
      local chat = chatmap[bufnr]
      if not chat then
        vim.notify("[CodeCompanion.nvim]\nChat session has been deleted", vim.log.levels.ERROR)
      else
        chat:submit()
      end
    end,
  })

  if config.options.display.chat.show_settings then
    -- Virtual text for the settings
    api.nvim_create_autocmd("InsertLeave", {
      buffer = bufnr,
      callback = function()
        local settings = parse_settings(bufnr)
        local errors = schema.validate(schema.static.chat_settings, settings)
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

  -- Enable cmp and add virtual text to the empty buffer
  local bufenter_autocmd
  bufenter_autocmd = api.nvim_create_autocmd("BufEnter", {
    buffer = bufnr,
    callback = function()
      if #_G.codecompanion_chats == 0 then
        local ns_id = api.nvim_create_namespace("CodeCompanionChatVirtualText")
        api.nvim_buf_set_extmark(bufnr, ns_id, api.nvim_buf_line_count(bufnr) - 1, 0, {
          virt_text = { { "Save the buffer to send a message to OpenAI...", "CodeCompanionVirtualText" } },
          virt_text_pos = "eol",
        })
      end

      local has_cmp, cmp = pcall(require, "cmp")
      if has_cmp then
        if not registered_cmp then
          require("cmp").register_source("codecompanion", require("cmp_codecompanion").new())
          registered_cmp = true
        end
        cmp.setup.buffer({
          enabled = true,
          sources = {
            { name = "codecompanion" },
          },
        })
      end
      api.nvim_del_autocmd(bufenter_autocmd)
    end,
  })

  -- Clear the virtual text when the user starts typing
  if #_G.codecompanion_chats == 0 then
    local insertenter_autocmd
    insertenter_autocmd = api.nvim_create_autocmd("InsertEnter", {
      buffer = bufnr,
      callback = function()
        local ns_id = api.nvim_create_namespace("CodeCompanionChatVirtualText")
        api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

        api.nvim_del_autocmd(insertenter_autocmd)
      end,
    })
  end

  -- Save the buffer to memory when closed
  api.nvim_create_autocmd("BufWinLeave", {
    buffer = bufnr,
    callback = function()
      local data = {}
      data.type = args.type
      data.settings, data.messages = parse_messages_buffer(bufnr)
      table.insert(_G.codecompanion_chats, data)
    end,
  })
end

---@class CodeCompanion.Chat
---@field client CodeCompanion.Client
---@field bufnr integer
---@field settings CodeCompanion.ChatSettings
local Chat = {}

---@class CodeCompanion.ChatArgs
---@field client CodeCompanion.Client
---@field context table
---@field messages nil|CodeCompanion.ChatMessage[]
---@field show_buffer nil|boolean
---@field settings nil|CodeCompanion.ChatSettings
---@field type nil|string
---@field conversation nil|CodeCompanion.Conversation

---@param args CodeCompanion.ChatArgs
function Chat.new(args)
  local bufnr
  if config.options.display.chat.type == "float" then
    bufnr = api.nvim_create_buf(false, true)
  else
    bufnr = api.nvim_create_buf(true, false)
  end
  local winid = api.nvim_get_current_win()

  api.nvim_buf_set_name(bufnr, string.format("[CodeCompanion] %d", math.random(10000000)))
  api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
  api.nvim_buf_set_option(bufnr, "filetype", "codecompanion")
  api.nvim_buf_set_option(bufnr, "syntax", "markdown")
  api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")

  watch_cursor()
  chat_autocmds(bufnr, args)

  local settings = args.settings or schema.get_default(schema.static.chat_settings, args.settings)

  local self = setmetatable({
    bufnr = bufnr,
    client = args.client,
    context = args.context,
    conversation = args.conversation,
    settings = settings,
    type = args.type,
  }, { __index = Chat })

  local keys = require("codecompanion.utils.keymaps")
  keys.set_keymaps(config.options.keymaps, bufnr, self)

  chatmap[bufnr] = self
  render_messages(bufnr, settings, args.messages or {}, args.context or {})
  display_tokens(bufnr)

  for k, v in pairs(config.options.display.chat.win_options) do
    api.nvim_set_option_value(k, v, { scope = "local", win = winid })
  end

  if config.options.display.chat.type == "buffer" and args.show_buffer then
    api.nvim_set_current_buf(bufnr)
    util.buf_scroll_to_end(bufnr)
  end

  if self.conversation then
    create_conversation_autocmds(bufnr, self.conversation)
  end
  create_conversation_commands(bufnr)

  if config.options.display.chat.type == "float" then
    self:open_float(bufnr, config.options.display.chat.float)
  end

  return self
end

---@param bufnr number
function Chat:open_float(bufnr, opts)
  local ui = require("codecompanion.utils.ui")

  local total_width = vim.o.columns
  local total_height = ui.get_editor_height()
  local width = total_width - 2 * opts.padding
  if opts.border ~= "none" then
    width = width - 2 -- The border consumes 1 col on each side
  end
  if opts.max_width > 0 then
    width = math.min(width, opts.max_width)
  end

  local height = total_height - 2 * opts.padding
  if opts.max_height > 0 then
    height = math.min(height, opts.max_height)
  end

  local row = math.floor((total_height - height) / 2)
  local col = math.floor((total_width - width) / 2) - 1 -- adjust for border width

  api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = opts.border,
    zindex = 45,
    title = "Code Companion",
    title_pos = "center",
  })

  util.buf_scroll_to_end(bufnr)
end

function Chat:submit()
  local settings, messages = parse_messages_buffer(self.bufnr)

  if not messages or #messages == 0 then
    return
  end

  vim.bo[self.bufnr].modified = false
  vim.bo[self.bufnr].modifiable = false
  api.nvim_buf_set_keymap(self.bufnr, "n", "q", "", {
    noremap = true,
    silent = true,
    callback = function()
      _G.codecompanion_jobs[self.bufnr].status = "stopping"
    end,
  })

  local function finalize()
    vim.bo[self.bufnr].modified = false
    vim.bo[self.bufnr].modifiable = true
  end

  local function render_buffer()
    local line_count = api.nvim_buf_line_count(self.bufnr)
    local current_line = api.nvim_win_get_cursor(0)[1]
    local cursor_moved = current_line == line_count

    render_messages(self.bufnr, settings, messages, {})

    if cursor_moved and util.buf_is_active(self.bufnr) then
      util.buf_scroll_to_end()
    end
  end

  local new_message = messages[#messages]

  if new_message and new_message.role == "user" and new_message.content == "" then
    return finalize()
  end

  self.client:stream_chat(
    vim.tbl_extend("keep", settings, {
      messages = messages,
    }),
    self.bufnr,
    function(err, chunk, done)
      if err then
        vim.notify("Error: " .. err, vim.log.levels.ERROR)
        return finalize()
      end

      if chunk then
        log:debug("chat chunk: %s", chunk)
        local delta = chunk.choices[1].delta
        if delta.role and delta.role ~= new_message.role then
          new_message = { role = delta.role, content = "" }
          table.insert(messages, new_message)
        end

        if delta.content then
          new_message.content = new_message.content .. delta.content
        end

        render_buffer()
      end

      if done then
        api.nvim_buf_del_keymap(self.bufnr, "n", "q")
        table.insert(messages, { role = "user", content = "" })
        render_buffer()
        display_tokens(self.bufnr)
        finalize()
      end
    end
  )
end

---@param opts nil|table
---@return nil|string Table
function Chat:_get_settings_key(opts)
  opts = vim.tbl_extend("force", opts or {}, {
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

function Chat:on_cursor_moved()
  local key_name, node = self:_get_settings_key()
  if not key_name or not node then
    vim.diagnostic.set(config.INFO_NS, self.bufnr, {})
    return
  end
  local key_schema = schema.static.chat_settings[key_name]

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
  else
    vim.diagnostic.set(config.INFO_NS, self.bufnr, {})
  end
end

function Chat:complete(request, callback)
  local items = {}
  local cursor = api.nvim_win_get_cursor(0)
  local key_name, node = self:_get_settings_key({ pos = { cursor[1] - 1, 1 } })
  if not key_name or not node then
    callback({ items = items, isIncomplete = false })
    return
  end

  local key_schema = schema.static.chat_settings[key_name]
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

---@param bufnr nil|integer
---@return nil|CodeCompanion.Chat
function Chat.buf_get_chat(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = api.nvim_get_current_buf()
  end
  return chatmap[bufnr]
end

return Chat
