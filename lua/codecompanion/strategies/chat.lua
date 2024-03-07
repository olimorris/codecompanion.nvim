local client = require("codecompanion.client")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local schema = require("codecompanion.schema")
local ui = require("codecompanion.utils.ui")
local utils = require("codecompanion.utils.util")
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
    config_settings[bufnr] = config.options.adapters.chat:get_default_settings()

    log:debug("Using the settings from the user's config: %s", config_settings[bufnr])
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
---@return table
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
---@param settings table
---@param messages table
---@param context table
local function render_messages(bufnr, settings, messages, context)
  local lines = {}
  if config.options.display.chat.show_settings then
    lines = { "---" }
    local keys = schema.get_ordered_keys(config.options.adapters.chat.schema)
    for _, key in ipairs(keys) do
      table.insert(lines, string.format("%s: %s", key, yaml.encode(settings[key])))
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
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = modifiable
end

local display_tokens = function(bufnr)
  if config.options.display.chat.show_token_count then
    require("codecompanion.utils.tokens").display_tokens(bufnr)
  end
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
  local aug = api.nvim_create_augroup("CodeCompanion", {
    clear = false,
  })

  -- Submit the chat
  api.nvim_create_autocmd("BufWriteCmd", {
    group = aug,
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
      group = aug,
      buffer = bufnr,
      callback = function()
        local settings = parse_settings(bufnr)
        local errors = schema.validate(config.options.adapters.chat.schema, settings)
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
    group = aug,
    buffer = bufnr,
    callback = function()
      if ui.buf_is_empty(bufnr) then
        local ns_id = api.nvim_create_namespace("CodeCompanionChatVirtualText")
        api.nvim_buf_set_extmark(bufnr, ns_id, api.nvim_buf_line_count(bufnr) - 1, 0, {
          virt_text = { { config.options.intro_message, "CodeCompanionVirtualText" } },
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
  if utils.count(_G.codecompanion_chats) == 0 then
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
      if request.data.buf ~= bufnr or request.data.action ~= "hide_buffer" then
        return
      end

      _G.codecompanion_last_chat_buffer = bufnr

      if _G.codecompanion_chats[bufnr] == nil then
        local description
        local _, messages = parse_messages_buffer(bufnr)

        if messages[1] and messages[1].content then
          description = messages[1].content
        else
          description = "[No messages]"
        end

        _G.codecompanion_chats[bufnr] = {
          name = "Chat " .. utils.count(_G.codecompanion_chats) + 1,
          description = description,
        }
      end
    end,
  })

  api.nvim_create_autocmd("User", {
    desc = "Remove the chat buffer from the stored chats",
    group = aug,
    pattern = "CodeCompanionChat",
    callback = function(request)
      if request.data.buf ~= bufnr or request.data.action ~= "close_buffer" then
        return
      end

      if _G.codecompanion_last_chat_buffer == bufnr then
        _G.codecompanion_last_chat_buffer = nil
      end

      _G.codecompanion_chats[bufnr] = nil

      if _G.codecompanion_jobs[request.data.buf] then
        _G.codecompanion_jobs[request.data.buf].handler:shutdown()
      end
      api.nvim_exec_autocmds("User", { pattern = "CodeCompanionRequest", data = { status = "finished" } })
      api.nvim_buf_delete(request.data.buf, { force = true })
    end,
  })
end

---@class CodeCompanion.Chat
---@field bufnr integer
---@field settings table
local Chat = {}

---@class CodeCompanion.ChatArgs
---@field adapter CodeCompanion.Adapter
---@field context table
---@field messages nil|table
---@field show_buffer nil|boolean
---@field auto_submit nil|boolean
---@field settings nil|table
---@field type nil|string
---@field saved_chat nil|string

---@param args CodeCompanion.ChatArgs
function Chat.new(args)
  local bufnr
  local winid

  if config.options.display.chat.type == "float" then
    bufnr = api.nvim_create_buf(false, false)
  else
    bufnr = api.nvim_create_buf(true, false)
    winid = api.nvim_get_current_win()
  end

  api.nvim_buf_set_name(bufnr, string.format("[CodeCompanion] %d", math.random(10000000)))
  api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
  api.nvim_buf_set_option(bufnr, "filetype", "codecompanion")
  api.nvim_buf_set_option(bufnr, "syntax", "markdown")
  vim.b[bufnr].codecompanion_type = "chat"

  ui.set_buf_options(bufnr, config.options.display.chat.buf_options)

  watch_cursor()
  chat_autocmds(bufnr, args)

  local settings = args.settings or schema.get_default(config.options.adapters.chat.schema, args.settings)

  local self = setmetatable({
    bufnr = bufnr,
    context = args.context,
    saved_chat = args.saved_chat,
    settings = settings,
    type = args.type,
  }, { __index = Chat })

  chatmap[bufnr] = self

  local keys = require("codecompanion.utils.keymaps")
  keys.set_keymaps(config.options.keymaps, bufnr, self)

  render_messages(bufnr, settings, args.messages or {}, args.context or {})

  if args.saved_chat then
    display_tokens(bufnr)
  end

  if config.options.display.chat.type == "float" then
    winid = ui.open_float(bufnr, {
      display = config.options.display.chat.float_options,
    })
  end

  if config.options.display.chat.type == "buffer" and args.show_buffer then
    api.nvim_set_current_buf(bufnr)
  end

  ui.set_win_options(winid, config.options.display.chat.win_options)
  vim.cmd("setlocal formatoptions-=t")
  ui.buf_scroll_to_end(bufnr)

  if args.auto_submit then
    self:submit()
  end

  return self
end

function Chat:submit()
  local settings, messages = parse_messages_buffer(self.bufnr)

  if not messages or #messages == 0 then
    return
  end

  vim.bo[self.bufnr].modified = false
  vim.bo[self.bufnr].modifiable = false

  local function finalize()
    vim.bo[self.bufnr].modified = false
    vim.bo[self.bufnr].modifiable = true
  end

  local role = ""
  local function render_new_messages(data)
    local total_lines = api.nvim_buf_line_count(self.bufnr)
    local current_line = api.nvim_win_get_cursor(0)[1]
    local cursor_moved = current_line == total_lines

    local lines = {}
    if data.role and data.role ~= role then
      role = data.role
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

      local last_line = api.nvim_buf_get_lines(self.bufnr, total_lines - 1, total_lines, false)[1]
      local last_col = last_line and #last_line or 0
      api.nvim_buf_set_text(self.bufnr, total_lines - 1, last_col, total_lines - 1, last_col, lines)

      vim.bo[self.bufnr].modified = false
      vim.bo[self.bufnr].modifiable = modifiable

      if cursor_moved and ui.buf_is_active(self.bufnr) then
        ui.buf_scroll_to_end(self.bufnr)
      elseif not ui.buf_is_active(self.bufnr) then
        ui.buf_scroll_to_end(self.bufnr)
      end
    end
  end

  local current_message = messages[#messages]

  if current_message and current_message.role == "user" and current_message.content == "" then
    return finalize()
  end

  -- log:trace("----- For Adapter test creation -----\nMessages: %s\n ---------- // END ----------", messages)
  -- log:trace("Settings: %s", settings)

  local adapter = config.options.adapters.chat

  client.new():stream(adapter:set_params(settings), messages, self.bufnr, function(err, data, done)
    if err then
      vim.notify("Error: " .. err, vim.log.levels.ERROR)
      return finalize()
    end

    if done then
      render_new_messages({ role = "user", content = "" })
      display_tokens(self.bufnr)
      return finalize()
    end

    if data then
      local result = adapter.callbacks.chat_output(data)

      if result and result.status == "success" then
        render_new_messages(result.output)
      elseif result and result.status == "error" then
        vim.api.nvim_exec_autocmds(
          "User",
          { pattern = "CodeCompanionRequest", data = { buf = self.bufnr, action = "stop_request" } }
        )
        vim.notify("Error: " .. result.output, vim.log.levels.ERROR)
        return finalize()
      end
    end
  end)
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
  local key_schema = config.options.adapters.chat.schema[key_name]

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

  local key_schema = config.options.adapters.chat.schema[key_name]
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

---@param bufnr nil|integer
---@return table
---@return nil|CodeCompanion.Chat
function Chat.buf_get_messages(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = api.nvim_get_current_buf()
  end
  return parse_messages_buffer(bufnr)
end

return Chat
