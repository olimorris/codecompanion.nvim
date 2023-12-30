local Client = require("openai.client")
local util = require("openai.utils.util")
local M = {}

local _client
---@return nil|openai.Client
local function get_client()
  if not _client then
    local secret_key = os.getenv("OPENAI_API_KEY")
    if not secret_key then
      vim.notify("Could not find env variable: OPENAI_API_KEY", vim.log.levels.ERROR)
      return nil
    end
    _client = Client.new({
      secret_key = secret_key,
      organization = os.getenv("OPENAI_ORG"),
    })
  end
  return _client
end

---@param bufnr nil|integer
---@return nil|openai.Chat
M.buf_get_chat = function(bufnr)
  return require("openai.actions.chat").buf_get_chat(bufnr)
end

M.chat = function()
  local client = get_client()
  if not client then
    return
  end
  local Chat = require("openai.actions.chat")
  local chat = Chat.new({
    client = client,
  })
  vim.api.nvim_win_set_buf(0, chat.bufnr)
  util.scroll_to_end(0)
  vim.bo[chat.bufnr].filetype = "markdown"
end

local last_edit
---@param line1 integer
---@param line2 integer
---@param mode string
M.edit = function(line1, line2, mode)
  local client = get_client()
  if not client then
    return
  end
  local ChatEdit = require("openai.actions.edit")
  last_edit = ChatEdit.new({
    line1 = line1,
    line2 = line2,
    mode = mode,
    client = client,
  })
  last_edit:start(function()
    util.set_dot_repeat("repeat_last_edit")
  end)
end

M.repeat_last_edit = function()
  if last_edit and vim.api.nvim_get_current_buf() == last_edit.bufnr then
    last_edit:start(function()
      util.set_dot_repeat("repeat_last_edit")
    end)
  end
end

M.setup = function()
  require("openai.config").setup()
end

return M
