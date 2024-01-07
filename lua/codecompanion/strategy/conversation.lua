local chat = require("codecompanion.strategy.chat")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local prefix = config.options.conversations.save_dir .. "/"
local suffix = ".json"

local function get_current_datetime()
  return os.date("%Y-%m-%d_%H:%M:%S")
end

---@param bufnr number
---@param name string
local function rename_buffer(bufnr, name)
  vim.api.nvim_buf_set_name(bufnr, "[OpenAI Chat] " .. name .. ".md")
end

---@class CodeCompanion.Conversation
---@field filename nil|string The conversation name
---@field cwd string The current working directory of the editor
local Conversation = {}

---@class CodeCompanion.SessionArgs
---@field filename nil|string The conversation name
---@field cwd string The current working directory of the editor

---@param args CodeCompanion.SessionArgs
---@return CodeCompanion.Conversation
function Conversation.new(args)
  log:trace("Initiating Conversation")

  local self = setmetatable({
    filename = args.filename,
    cwd = args.cwd or vim.fn.getcwd(),
  }, { __index = Conversation })

  return self
end

---@param filename string
---@param bufnr number
---@param conversation table
local function save(filename, bufnr, conversation)
  local path = prefix .. filename .. suffix

  local match = path:match("(.*/)")
  if match then
    vim.fn.mkdir(match, "p")
  end

  local file, err = io.open(path, "w")
  if file ~= nil then
    log:debug('Conversation: "%s.json" saved', filename)
    file:write(vim.json.encode(conversation))
    file:close()
  else
    log:debug("Conversation could not be saved. Error: %s", err)
    vim.notify("[CodeCompanion.nvim]\nCannot save conversation: " .. err, vim.log.levels.ERROR)
  end

  rename_buffer(bufnr, filename)
end

---@param bufnr number
---@param messages table
function Conversation:save(bufnr, settings, messages)
  local tokens = require("codecompanion.utils.tokens")
  local files = require("codecompanion.utils.files")

  local conversation = {
    meta = {
      dir = files.replace_home(self.cwd),
      tokens = tokens.get_tokens(messages),
      updated_at = get_current_datetime(),
    },
    settings = settings,
    messages = messages,
  }

  if not self.filename then
    log:debug("Conversation: No filename provided, skipping save")
    return
  end

  return save(self.filename, bufnr, conversation)
end

---@param opts nil|table
function Conversation:list(opts)
  local paths = vim.fn.glob(prefix .. "*" .. suffix, false, true)
  local conversations = {}

  for _, path in ipairs(paths) do
    local file_content = table.concat(vim.fn.readfile(path), "\n")
    local conversation = vim.fn.json_decode(file_content)

    if conversation and conversation.meta and conversation.meta.updated_at then
      table.insert(conversations, {
        tokens = conversation.meta.tokens,
        filename = path:match("([^/]+)%.json$"),
        path = path,
        dir = conversation.meta.dir,
        updated_at = conversation.meta.updated_at,
        strategy = "conversations", -- This allows us to call this very strategy from the picker
      })
    end
  end

  if opts and opts.sort then
    table.sort(conversations, function(a, b)
      return a.updated_at > b.updated_at -- Sort in descending order
    end)
  end

  return conversations
end

---@param client CodeCompanion.Client
---@param opts table
function Conversation:load(client, opts)
  log:debug("Loading conversation: %s", opts)

  self.filename = opts.filename
  local content = vim.fn.json_decode(table.concat(vim.fn.readfile(opts.path), "\n"))

  local chat_buf = chat.new({
    client = client,
    settings = content.settings,
    messages = content.messages,
    show_buffer = true,
    conversation = self,
  })

  rename_buffer(chat_buf.bufnr, opts.filename)
end

return Conversation
