local config = require("codecompanion.config")
local parser = require("codecompanion.interactions.chat.parser")

local files = require("codecompanion.utils.files")

local M = {}

---The absolute path of a link that points at a file on disk
---@param path string
---@return string|nil
local function resolve_local_file(path)
  path = vim.fs.abspath(vim.fs.normalize(path))
  if files.exists(path) and not files.is_dir(path) then
    return path
  end
end

---@param chat CodeCompanion.Chat
---@param path string
---@return string|nil
local function attach_file(chat, path)
  local slash_command = require("codecompanion.interactions.shared.slash_commands.file").new({
    Chat = chat,
    config = config.interactions.chat.slash_commands.file,
  })
  if slash_command:output({ path = path }) then
    return vim.fn.fnamemodify(path, ":.")
  end
end

---@param chat CodeCompanion.Chat
---@param url string
---@return string|nil
local function attach_url(chat, url)
  chat:_set_status("fetching", "Resolving URL...")
  vim.cmd("redraw")

  local attached = require("codecompanion.interactions.chat.slash_commands.builtin.fetch").fetch_sync({
    cache = false,
    chat = chat,
    url = url,
  })

  chat:_set_status("fetching", attached and "Resolved..." or "Could not resolve URL")
  return attached and url or nil
end

---Attach any files or URLs that the user has linked to in their message
---@param opts { chat: CodeCompanion.Chat, message: table }
---@return nil
function M.attach(opts)
  local chat = opts.chat
  local context_paths = parser.context_paths(chat, { start_range = chat.header_line })
  if not context_paths then
    return
  end

  local attached = {}
  for _, context_path in ipairs(context_paths) do
    local path = resolve_local_file(context_path.destination)
    local source = path or context_path.destination:match("^https?://.+")
    if source then
      if attached[source] == nil then
        attached[source] = (path and attach_file(chat, path) or attach_url(chat, source)) or false
      end

      local replacement = attached[source]
      if replacement then
        replacement = replacement:gsub("%%", "%%%%")
        opts.message.content = vim.trim(opts.message.content:gsub(vim.pesc(context_path.markdown), replacement))
      end
    end
  end
end

return M
