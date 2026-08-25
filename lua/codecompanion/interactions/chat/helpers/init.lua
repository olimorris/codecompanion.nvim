local config = require("codecompanion.config")

local buf_utils = require("codecompanion.utils.buffers")
local files = require("codecompanion.utils.files")
local formatters = require("codecompanion.context.formatters")
local log = require("codecompanion.utils.log")

local M = {}

local api = vim.api
local fmt = string.format

---Establishes the connection, authenticates, creates a session and links the buffer.
---@param chat CodeCompanion.Chat
---@param cb? function
---@return nil
function M.create_acp_connection(chat, cb)
  ---Run async so as not to block the UI
  local async_utils = require("codecompanion.utils.async")

  local function call_cb()
    if cb then
      vim.schedule(cb)
    end
  end

  async_utils.sync(function()
    local ACPHandler = require("codecompanion.interactions.chat.acp.handler")
    local handler = ACPHandler.new(chat)

    if not handler:ensure_connection() then
      return call_cb()
    end

    handler:ensure_session()
    call_cb()
  end)()
end

---Return a code fence longer than any successive backtick counts in the content
---@param content string
---@return string
function M.code_fence(content)
  local longest = 3
  for run in content:gmatch("`+") do
    longest = math.max(longest, #run)
  end
  return string.rep("`", longest + 1)
end

---Format the given role without any separator
---@param role string
---@return string
function M.format_role(role)
  if config.display.chat.show_header_separator then
    role = vim.trim(role:gsub(config.display.chat.separator, ""))
  end
  return role
end

---Strip any context from the messages - The LLM doesn't need to see this
---@param messages table
---@return table
function M.strip_context(messages)
  local i = 1
  while messages[i] and messages[i]:sub(1, 1) == ">" do
    table.remove(messages, i)
    -- we do not increment i, since removing shifts everything down
  end
  return messages
end

---Get the keymaps for the slash commands
---@param slash_commands table
---@return table
function M.slash_command_keymaps(slash_commands)
  local keymaps = {}
  for k, v in pairs(slash_commands) do
    if v.keymaps then
      keymaps[k] = {}
      keymaps[k].description = v.description
      keymaps[k].callback = "keymaps." .. k
      keymaps[k].modes = v.keymaps.modes
    end
  end

  return keymaps
end

---Check if the messages contain any user messages
---@param messages table The list of messages to check
---@return boolean
function M.has_user_messages(messages)
  return vim.iter(messages):any(function(msg)
    return msg.role == config.constants.USER_ROLE
  end)
end

---Helper function to update the chat settings and model if changed
---@param chat CodeCompanion.Chat
---@param settings table The new settings to apply
---@return nil
function M.apply_settings_and_model(chat, settings)
  local old_model = chat.settings.model
  chat:apply_settings(settings)
  if old_model and old_model ~= settings.model then
    chat:change_model({ model = settings.model })
  end
end

---Determine if a tag exists in the messages table
---@param tag string
---@param messages CodeCompanion.Chat.Messages
---@return boolean
function M.has_tag(tag, messages)
  for _, msg in ipairs(messages) do
    if msg._meta and msg._meta.tag == tag then
      return true
    end
  end
  return false
end

---Resolve which MCP servers should be added to new chat buffers
---@return table<string> server_names List of server names to add to chat
function M.mcp_servers_to_add_to_chat()
  local mcp_cfg = config.mcp
  local default_servers = mcp_cfg.opts and mcp_cfg.opts.default_servers

  if type(default_servers) == "table" then
    return vim.deepcopy(default_servers)
  end

  return {}
end

---Start MCP servers and add their tools to the chat buffer
---@param chat CodeCompanion.Chat
---@param server_names table<string> List of MCP server names
---@return nil
function M.start_mcp_servers(chat, server_names)
  local mcp = require("codecompanion.mcp")

  ---Add an MCP server's tool group to the chat buffer
  ---@param name string
  local function add_tools(name)
    chat.tools:refresh({ adapter = chat.adapter })
    chat.tool_registry:add(mcp.tool_prefix() .. name, { config = chat.tools.tools_config })
    log:debug("Added MCP server tools for `%s` to chat %d", name, chat.id)
  end

  for _, name in ipairs(server_names) do
    local status = mcp.get_status()
    local server_status = status[name]

    if server_status and server_status.ready and server_status.tool_count > 0 then
      add_tools(name)
    else
      mcp.enable_server(name, {
        on_tools_loaded = function()
          add_tools(name)
        end,
      })
    end
  end
end

---Remove all MCP tool groups from the chat's tool registry
---@param chat CodeCompanion.Chat
---@return nil
function M.remove_mcp_tools(chat)
  local mcp = require("codecompanion.mcp")
  local prefix = mcp.tool_prefix()

  for group_name, _ in pairs(chat.tool_registry.groups) do
    if group_name:sub(1, #prefix) == prefix then
      chat.tool_registry:remove_group(group_name)
    end
  end
end

---Determine if context has already been added to the messages stack
---@param context string
---@param messages CodeCompanion.Chat.Messages
---@return boolean
function M.has_context(context, messages)
  return vim.tbl_contains(
    vim.tbl_map(function(msg)
      return msg.context and msg.context.id
    end, messages),
    context
  )
end

---Read a file/buffer's content
---@param args { bufnr: number, path: string, range?: table }
---@return string
local function read_content(args)
  if api.nvim_buf_is_loaded(args.bufnr) then
    return buf_utils.get_content(args.bufnr, args.range)
  end

  local content = files.read(args.path)
  if content == "" then
    error("Could not read the file: " .. args.path)
  end

  return vim.trim(content)
end

---Read a buffer's content for an LLM, applying the formatter registered for its extension
---@param bufnr number
---@param path string
---@return string|nil
function M.read_buffer_for_llm(bufnr, path)
  local ok, content = pcall(function()
    return (formatters.apply({ path = path, raw = read_content({ bufnr = bufnr, path = path }) }))
  end)
  if not ok then
    return nil
  end

  return content
end

---Format buffer content with XML wrapper for LLM consumption
---@param bufnr number
---@param path string
---@param opts? { message?: string, range?: table }
---@return { content: string, filename: string, id: string }
function M.format_buffer_for_llm(bufnr, path, opts)
  opts = opts or {}

  local content = read_content({ bufnr = bufnr, path = path, range = opts.range })

  -- A range is a slice of the buffer, so whole-file formatters do not apply
  local formatted = false
  if not opts.range then
    content, formatted = formatters.apply({ path = path, raw = content })
  end

  if not formatted then
    local filetype = api.nvim_buf_is_loaded(bufnr) and buf_utils.get_info(bufnr).filetype
      or vim.filetype.match({ filename = path })
    local numbered_content = buf_utils.add_line_numbers(content)
    local code_fence = M.code_fence(numbered_content)
    content = fmt(
      [[%s%s
%s
%s]],
      code_fence,
      filetype,
      numbered_content,
      code_fence
    )
  end

  local filename = vim.fn.fnamemodify(path, ":t")

  -- Generate consistent ID using relative path for conciseness
  local id = "<buf>" .. vim.fn.fnamemodify(path, ":.") .. "</buf>"

  local message = opts.message or "File content"

  return {
    content = fmt(
      [[<attachment filepath="%s" buffer_number="%s">%s:
%s
</attachment>]],
      path,
      bufnr,
      message,
      content
    ),
    id = id,
    filename = filename,
  }
end

---Read a file's content for an LLM, applying the formatter registered for its extension
---@param path string
---@return string|nil
function M.read_file_for_llm(path)
  local ok, content = pcall(function()
    return (formatters.apply({ path = path, raw = files.read(path) }))
  end)

  if not ok then
    return nil
  end

  return content
end

---Format file content with XML wrapper for LLM consumption
---@param path string
---@param opts? { message?: string, range?: table }
---@return { content: string, filetype: string, id: string, path: string, raw: string }
function M.format_file_for_llm(path, opts)
  opts = opts or {}

  local raw_content = files.read(path)
  local filetype = vim.filetype.match({ filename = path })

  local file_contents, formatted = formatters.apply({ path = path, raw = raw_content })
  if not formatted then
    local code_fence = M.code_fence(raw_content)
    file_contents = fmt(
      [[%s%s
%s
%s]],
      code_fence,
      filetype,
      raw_content,
      code_fence
    )
  end

  local content
  if opts.message then
    content = fmt(
      [[%s

%s]],
      opts.message,
      file_contents
    )
  else
    content = fmt(
      [[<attachment filepath="%s">%s:
%s
</attachment>]],
      path,
      "Here is the content from the file",
      file_contents
    )
  end

  return {
    content = content,
    filetype = filetype,
    id = "<file>" .. vim.fn.fnamemodify(path, ":.") .. "</file>",
    path = path,
    raw = raw_content,
  }
end

---Add line numbers with an offset to content
---@param content string
---@param start_line number The starting line number
---@return string
local function add_line_numbers_from(content, start_line)
  local formatted = {}
  local lines = vim.split(content, "\n")
  for i, line in ipairs(lines) do
    table.insert(formatted, fmt("%d |%s", start_line + i - 1, line))
  end

  return table.concat(formatted, "\n")
end

---Format a single viewport range for LLM consumption
---@param bufnr number
---@param range table {start_line, end_line}
---@return string content The XML-wrapped content
---@return string id The context ID
function M.format_viewport_range_for_llm(bufnr, range)
  local info = buf_utils.get_info(bufnr)
  local filepath = info.path
  local start_line, end_line = range[1], range[2]

  local buffer_content = buf_utils.get_content(bufnr, { start_line - 1, end_line })
  local numbered_content = add_line_numbers_from(buffer_content, start_line)

  local code_fence = M.code_fence(numbered_content)
  local content = fmt(
    [[%s%s
%s
%s]],
    code_fence,
    info.filetype,
    numbered_content,
    code_fence
  )

  local excerpt_info = fmt("Excerpt from %s, lines %d to %d", filepath, start_line, end_line)

  local formatted_content = fmt(
    [[<attachment filepath="%s" buffer_number="%s">%s:
%s
</attachment>]],
    filepath,
    bufnr,
    excerpt_info,
    content
  )

  local id = fmt("<viewport>%s:%d-%d</viewport>", vim.fn.fnamemodify(filepath, ":."), start_line, end_line)

  return formatted_content, id
end

---Format viewport content with XML wrapper for LLM consumption
---@param buf_lines table Buffer lines from get_visible_lines()
---@return string content The XML-wrapped content for all visible buffers
function M.format_viewport_for_llm(buf_lines)
  local formatted = {}

  for bufnr, ranges in pairs(buf_lines) do
    for _, range in ipairs(ranges) do
      local content, _ = M.format_viewport_range_for_llm(bufnr, range)
      table.insert(formatted, content)
    end
  end

  return table.concat(formatted, "\n\n")
end

---Returns the number of tokens that trigger context management for a given operation
---@param adapter CodeCompanion.HTTPAdapter
---@param opts? { operation?: "editing"|"compaction" } defaults to "compaction"
---@return number
function M.trigger_context_management(adapter, opts)
  opts = opts or {}
  local operation = opts.operation or "compaction"

  local context_management = config.interactions.chat.opts.context_management
  local settings = context_management and context_management[operation]
  local trigger = settings and settings.trigger
  if trigger == nil then
    return 0
  end

  if trigger < 1 then
    local context_window = require("codecompanion.adapters.shared").context_window(adapter)
    if not context_window then
      log:debug("[Context Window] No context window for `%s` adapter, skipping %s trigger", adapter.name, operation)
      return 0
    end
    trigger = math.floor(trigger * context_window)
  end

  return trigger
end

return M
