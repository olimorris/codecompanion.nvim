local Chat = require("codecompanion.strategies.chat")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local prefix = config.options.saved_chats.save_dir .. "/"
local suffix = ".json"

local function get_current_datetime()
  return os.date("%Y-%m-%d_%H:%M:%S")
end

---@param bufnr number
---@param name string
local function rename_buffer(bufnr, name)
  vim.api.nvim_buf_set_name(bufnr, "[CodeCompanion Chat] " .. name .. ".md")
end

---@class CodeCompanion.SavedChat
---@field filename nil|string The saved_chat name
---@field cwd string The current working directory of the editor
local SavedChat = {}

---@class CodeCompanion.SessionArgs
---@field filename nil|string The saved_chat name
---@field cwd string The current working directory of the editor

---@param args CodeCompanion.SessionArgs
---@return CodeCompanion.SavedChat
function SavedChat.new(args)
  log:trace("Initiating saved chat")

  local self = setmetatable({
    filename = args.filename,
    cwd = args.cwd or vim.fn.getcwd(),
  }, { __index = SavedChat })

  return self
end

---@param filename string
---@param bufnr number
---@param saved_chat table
local function save(filename, bufnr, saved_chat)
  local path = prefix .. filename .. suffix

  local match = path:match("(.*/)")
  if match then
    vim.fn.mkdir(match, "p")
  end

  local file, err = io.open(path, "w")
  if file ~= nil then
    log:debug('Saved Chat: "%s.json" saved', filename)
    file:write(vim.json.encode(saved_chat))
    file:close()
    vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionChatSaved", data = { status = "finished" } })
  else
    log:debug("Saved chat could not be saved. Error: %s", err)
    vim.notify("[CodeCompanion.nvim]\nCannot save chat: " .. err, vim.log.levels.ERROR)
  end

  rename_buffer(bufnr, filename)
end

---@param bufnr number
---@param messages table
function SavedChat:save(bufnr, settings, messages)
  local tokens = require("codecompanion.utils.tokens")
  local files = require("codecompanion.utils.files")

  local saved_chat = {
    meta = {
      dir = files.replace_home(self.cwd),
      tokens = tokens.get_tokens(messages),
      updated_at = get_current_datetime(),
    },
    settings = settings,
    messages = messages,
  }

  if not self.filename then
    log:debug("Saved Chat: No filename provided, skipping save")
    return
  end

  return save(self.filename, bufnr, saved_chat)
end

---@param opts nil|table
function SavedChat:list(opts)
  local paths = vim.fn.glob(prefix .. "*" .. suffix, false, true)
  local saved_chats = {}

  for _, path in ipairs(paths) do
    local file_content = table.concat(vim.fn.readfile(path), "\n")
    local saved_chat = vim.fn.json_decode(file_content)

    if saved_chat and saved_chat.meta and saved_chat.meta.updated_at then
      table.insert(saved_chats, {
        tokens = saved_chat.meta.tokens .. " tokens",
        filename = path:match("([^/]+)%.json$"),
        path = path,
        dir = saved_chat.meta.dir,
        updated_at = saved_chat.meta.updated_at,
        strategy = "saved_chats", -- This allows us to call this very strategy from the picker
      })
    end
  end

  if opts and opts.sort then
    table.sort(saved_chats, function(a, b)
      return a.updated_at > b.updated_at -- Sort in descending order
    end)
  end

  return saved_chats
end

---@param opts table
function SavedChat:load(opts)
  log:debug("Loading saved chat: %s", opts)

  self.filename = opts.filename
  local content = vim.fn.json_decode(table.concat(vim.fn.readfile(opts.path), "\n"))

  local chat_buf = Chat.new({
    saved_chat = self.filename,
    messages = content.messages,
    settings = content.settings,
    show_buffer = true,
  })

  rename_buffer(chat_buf.bufnr, opts.filename)
end

function SavedChat:has_chats()
  return #self:list() > 0
end

return SavedChat
