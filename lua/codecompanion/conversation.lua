local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local prefix = config.options.conversations.save_dir .. "/"
local suffix = ".json"

local function get_current_datetime()
  return os.date("%Y-%m-%d_%H:%M:%S")
end

---@param bufnr number
---@param filename string
local function rename_buffer(bufnr, filename)
  vim.api.nvim_buf_set_name(bufnr, "[CodeCompanion] " .. filename)
end

---@class CodeCompanion.Conversation
---@field filename string The conversation name
---@field cwd string The current working directory of the editor
local Conversation = {}

---@class CodeCompanion.SessionArgs
---@field filename string The conversation name
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
  local conversation = {
    meta = {
      updated_at = get_current_datetime(),
      dir = self.cwd,
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

return Conversation
