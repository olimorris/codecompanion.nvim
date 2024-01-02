local Client = require("codecompanion.client")
local config = require("codecompanion.config")
local utils = require("codecompanion.utils.util")
local M = {}

local _client
---@return nil|codecompanion.Client
local function get_client()
  if not _client then
    local secret_key = os.getenv(config.config.api_key)
    if not secret_key then
      vim.notify(
        string.format("Could not find env variable: %s", config.config.api_key),
        vim.log.levels.ERROR
      )
      return nil
    end
    _client = Client.new({
      secret_key = secret_key,
      organization = os.getenv(config.config.org_api_key),
    })
  end
  return _client
end

---@param bufnr nil|integer
---@return nil|codecompanion.Chat
M.buf_get_chat = function(bufnr)
  return require("codecompanion.strategy.chat").buf_get_chat(bufnr)
end

M.chat = function()
  local client = get_client()
  if not client then
    return
  end
  local Chat = require("codecompanion.strategy.chat")
  local chat = Chat.new({
    client = client,
  })
  vim.api.nvim_win_set_buf(0, chat.bufnr)
  utils.scroll_to_end(0)
  vim.bo[chat.bufnr].filetype = "markdown"
end

local last_edit
---@param context nil|table
---@return nil|codecompanion.Assistant
M.assistant = function(context)
  local client = get_client()
  if not client then
    return
  end

  local Assistant = require("codecompanion.strategy.assistant")
  context = context or utils.get_context(vim.api.nvim_get_current_buf())

  last_edit = Assistant.new({
    context = context,
    client = client,
  })

  last_edit:start(function()
    utils.set_dot_repeat("repeat_last_edit")
  end)
end

M.repeat_last_edit = function()
  if last_edit and vim.api.nvim_get_current_buf() == last_edit.bufnr then
    last_edit:start(function()
      utils.set_dot_repeat("repeat_last_edit")
    end)
  end
end

M.commands = function()
  local client = get_client()
  if not client then
    return
  end

  local items = config.config.actions
  local context = utils.get_context(vim.api.nvim_get_current_buf())

  local strategies = {
    ["advisor"] = function(opts, prompts)
      return require("codecompanion.strategy.advisor")
        .new({
          context = context,
          client = client,
          opts = opts,
          prompts = prompts,
        })
        :start()
    end,
    ["author"] = function(opts, prompts)
      return require("codecompanion.strategy.author")
        .new({
          context = context,
          client = client,
          opts = opts,
          prompts = prompts,
        })
        :start()
    end,
    ["chat"] = function()
      return require("codecompanion").chat()
    end,
  }

  require("codecompanion.utils.ui").select(strategies, items)
end

M.setup = function()
  config.setup()
end

return M
