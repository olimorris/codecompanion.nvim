local config = require("codecompanion.config")

local Path = require("plenary.path")
local buf_utils = require("codecompanion.utils.buffers")
local log = require("codecompanion.utils.log")

local M = {}

local api = vim.api
local fmt = string.format

---Create a new ACP connection for the given chat
---@param chat CodeCompanion.Chat The chat instance
---@return boolean
function M.create_acp_connection(chat)
  local ACPHandler = require("codecompanion.interactions.chat.acp.handler")
  local handler = ACPHandler.new(chat)
  return handler:ensure_connection()
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
  return vim.tbl_contains(
    vim.tbl_map(function(msg)
      return msg._meta and msg._meta.tag
    end, messages),
    tag
  )
end

---Resolve which MCP servers should be added to new chat buffers
---@return table<string> server_names List of server names to add to chat
function M.mcp_servers_to_add_to_chat()
  local servers = {}
  local mcp_cfg = config.mcp
  local global_auto_start = mcp_cfg.auto_start
  local global_add_to_chat = mcp_cfg.add_to_chat

  for name, cfg in pairs(mcp_cfg.servers) do
    local opts = cfg.opts or {}

    local auto_start = opts.auto_start
    if auto_start == nil then
      auto_start = global_auto_start
    end

    if auto_start then
      local add_to_chat = opts.add_to_chat
      if add_to_chat == nil then
        add_to_chat = global_add_to_chat
      end
      if add_to_chat then
        table.insert(servers, name)
      end
    end
  end

  return servers
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

---Format buffer content with XML wrapper for LLM consumption
---@param bufnr number
---@param path string
---@param opts? { message?: string, range?: table }
---@return string content The XML-wrapped content
---@return string id The buffer context ID
---@return string filename The buffer filename
function M.format_buffer_for_llm(bufnr, path, opts)
  opts = opts or {}

  -- Handle unloaded buffers
  local content
  if not api.nvim_buf_is_loaded(bufnr) then
    local file_content = Path.new(path):read()
    if file_content == "" then
      error("Could not read the file: " .. path)
    end
    content = fmt(
      [[````%s
%s
````]],
      vim.filetype.match({ filename = path }),
      buf_utils.add_line_numbers(vim.trim(file_content))
    )
  else
    content = fmt(
      [[````%s
%s
````]],
      buf_utils.get_info(bufnr).filetype,
      buf_utils.add_line_numbers(buf_utils.get_content(bufnr, opts.range))
    )
  end

  local filename = vim.fn.fnamemodify(path, ":t")
  local relative_path = vim.fn.fnamemodify(path, ":.")

  -- Generate consistent ID
  local id = "<buf>" .. relative_path .. "</buf>"

  local message = opts.message or "File content"

  local formatted_content = fmt(
    [[<attachment filepath="%s" buffer_number="%s">%s:
%s</attachment>]],
    relative_path,
    bufnr,
    message,
    content
  )

  return formatted_content, id, filename
end

---Format buffer content with XML wrapper for LLM consumption
---@param path string
---@param opts? { message?: string, range?: table }
---@return string file_contents
---@return string id The context ID
---@return string relative_path The relative file path
---@return string ft The filetype
---@return string file_contents The raw file contents
function M.format_file_for_llm(path, opts)
  opts = opts or {}

  local file_contents = Path.new(path):read()

  local ft = vim.filetype.match({ filename = path })
  local relative_path = vim.fn.fnamemodify(path, ":.")
  local id = "<file>" .. relative_path .. "</file>"

  local content
  if opts.message then
    content = fmt(
      [[%s

````%s
%s
````]],
      opts.message,
      ft,
      file_contents
    )
  else
    content = fmt(
      [[<attachment filepath="%s">%s:

````%s
%s
````
</attachment>]],
      relative_path,
      "Here is the content from the file",
      ft,
      file_contents
    )
  end

  return content, id, relative_path, ft, file_contents
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
  local relative_path = vim.fn.fnamemodify(info.path, ":.")
  local start_line, end_line = range[1], range[2]

  local buffer_content = buf_utils.get_content(bufnr, { start_line - 1, end_line })
  local numbered_content = add_line_numbers_from(buffer_content, start_line)

  local content = fmt(
    [[````%s
%s
````]],
    info.filetype,
    numbered_content
  )

  local excerpt_info = fmt("Excerpt from %s, lines %d to %d", relative_path, start_line, end_line)

  local formatted_content = fmt(
    [[<attachment filepath="%s" buffer_number="%s">%s:
%s</attachment>]],
    relative_path,
    bufnr,
    excerpt_info,
    content
  )

  local id = fmt("<viewport>%s:%d-%d</viewport>", relative_path, start_line, end_line)

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

return M
