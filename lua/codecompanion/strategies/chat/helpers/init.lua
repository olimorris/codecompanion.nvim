local Path = require("plenary.path")

local base64 = require("codecompanion.utils.base64")
local buf_utils = require("codecompanion.utils.buffers")
local config = require("codecompanion.config")

local M = {}

local api = vim.api
local fmt = string.format

---Create a new ACP connection for the given chat
---@param chat CodeCompanion.Chat The chat instance
---@return boolean
function M.create_acp_connection(chat)
  local ACPHandler = require("codecompanion.strategies.chat.acp.handler")
  local handler = ACPHandler.new(chat)
  return handler:ensure_connection()
end

---Hide chat if floating diff is being used
---@param chat CodeCompanion.Chat The chat instance
---@return nil
function M.hide_chat_for_floating_diff(chat)
  local inline_config = config.display.diff.provider_opts.inline
  local diff_layout = inline_config.layout
  if diff_layout == "float" and config.display.chat.window.layout == "float" then
    if chat and chat.ui:is_visible() then
      chat.ui:hide()
    end
  end
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

---Base64 encode the given image
---@param image CodeCompanion.Image The image object containing the path and other metadata.
---@return CodeCompanion.Image|string The base64 encoded image string
function M.encode_image(image)
  local b64_content, b64_err = base64.encode(image.path)
  if b64_err then
    return b64_err
  end

  image.base64 = b64_content

  if not image.mimetype then
    image.mimetype = base64.get_mimetype(image.path)
  end

  return image
end

---Add an image to the chat buffer
---@param Chat CodeCompanion.Chat The chat instance
---@param image table The image object containing the path and other metadata
---@param opts table Options for adding the image
---@return nil
function M.add_image(Chat, image, opts)
  opts = opts or {}

  local id = "<image>" .. (image.id or image.path) .. "</image>"

  Chat:add_message({
    role = opts.role or config.constants.USER_ROLE,
    content = image.base64,
  }, {
    context = { id = id, mimetype = image.mimetype, path = image.id or image.path },
    _meta = { tag = "image" },
    visible = false,
  })

  Chat.context:add({
    bufnr = opts.bufnr or image.bufnr,
    id = id,
    path = image.path,
    source = opts.source or "codecompanion.strategies.chat.slash_commands.image",
  })
end

---Check if the messages contain any user messages
---@param messages table The list of messages to check
---@return boolean
function M.has_user_messages(messages)
  return vim.iter(messages):any(function(msg)
    return msg.role == config.constants.USER_ROLE
  end)
end

---Validate and normalize a path from tool args
---@param path string Raw path from tool args
---@return string|nil normalized_path Returns nil if path is invalid
function M.validate_and_normalize_path(path)
  local stat = vim.uv.fs_stat(path)
  if stat then
    return vim.fs.normalize(path)
  end
  local abs_path = vim.fs.abspath(path)
  local normalized_path = vim.fs.normalize(abs_path)
  stat = vim.uv.fs_stat(normalized_path)
  if stat then
    return normalized_path
  end
  -- Check for duplicate CWD and fix it
  local cwd = vim.uv.cwd()
  if normalized_path:find(cwd, 1, true) and normalized_path:find(cwd, #cwd + 2, true) then
    local fixed_path = normalized_path:gsub("^" .. vim.pesc(cwd) .. "/", "")
    fixed_path = vim.fs.normalize(fixed_path)
    stat = vim.uv.fs_stat(fixed_path)
    if stat then
      return fixed_path
    end
  end

  -- For non-existent files, still return the normalized path
  -- This allows tracking files that may be created during tool execution
  return normalized_path
end

---Helper function to update the chat settings and model if changed
---@param chat CodeCompanion.Chat
---@param settings table The new settings to apply
---@return nil
function M.apply_settings_and_model(chat, settings)
  local old_model = chat.settings.model
  chat:apply_settings(settings)
  if old_model and old_model ~= settings.model then
    chat:apply_model(settings.model)
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
      [[```%s
%s
```]],
      vim.filetype.match({ filename = path }),
      buf_utils.add_line_numbers(vim.trim(file_content))
    )
  else
    content = fmt(
      [[```%s
%s
```]],
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

```%s
%s
```]],
      opts.message,
      ft,
      file_contents
    )
  else
    content = fmt(
      [[<attachment filepath="%s">%s:

```%s
%s
```
</attachment>]],
      relative_path,
      "Here is the content from the file",
      ft,
      file_contents
    )
  end

  return content, id, relative_path, ft, file_contents
end

---Format viewport content with XML wrapper for LLM consumption
---@param buf_lines table Buffer lines from get_visible_lines()
---@return string content The XML-wrapped content for all visible buffers
function M.format_viewport_for_llm(buf_lines)
  local formatted = {}

  for bufnr, ranges in pairs(buf_lines) do
    local info = buf_utils.get_info(bufnr)
    local relative_path = vim.fn.fnamemodify(info.path, ":.")

    for _, range in ipairs(ranges) do
      local start_line, end_line = range[1], range[2]

      local buffer_content = buf_utils.get_content(bufnr, { start_line - 1, end_line })
      local content = fmt(
        [[```%s
%s
```]],
        info.filetype,
        buffer_content
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

      table.insert(formatted, formatted_content)
    end
  end

  return table.concat(formatted, "\n\n")
end

return M
