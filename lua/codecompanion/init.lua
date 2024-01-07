local Client = require("codecompanion.client")
local config = require("codecompanion.config")
local utils = require("codecompanion.utils.util")
local M = {}

local _client
---@return nil|CodeCompanion.Client
local function get_client()
  if not _client then
    local secret_key = os.getenv(config.options.api_key)
    if not secret_key then
      vim.notify(
        string.format(
          "[CodeCompanion.nvim]\nCould not find env variable: %s",
          config.options.api_key
        ),
        vim.log.levels.ERROR
      )
      return nil
    end
    _client = Client.new({
      secret_key = secret_key,
      organization = os.getenv(config.options.org_api_key),
    })
  end
  return _client
end

---@param bufnr nil|integer
---@return nil|CodeCompanion.Chat
M.buf_get_chat = function(bufnr)
  require("codecompanion.strategy.chat").buf_get_chat(bufnr)
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
---@return nil|CodeCompanion.Assistant
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

M.conversations = function()
  local client = get_client()
  if not client then
    return
  end

  local conversation = require("codecompanion.strategy.conversation")
  local conversations = conversation.new({}):list({ sort = true })

  if not conversations or #conversations == 0 then
    return vim.notify("[CodeCompanion.nvim]\nNo conversations found", vim.log.levels.WARN)
  end

  require("codecompanion.utils.ui").selector(conversations, {
    prompt = "Select a conversation",
    format = function(item)
      return { item.tokens, item.filename, item.dir }
    end,
    callback = function(selected)
      return conversation
        .new({
          filename = selected.filename,
        })
        :load(client, selected)
    end,
  })
end

M.actions = function()
  local client = get_client()
  if not client then
    return
  end

  local context = utils.get_context(vim.api.nvim_get_current_buf())

  local function picker(items, opts, callback)
    opts = opts or {}
    opts.prompt = opts.prompt or "Select an option"
    opts.columns = opts.columns or { "name", "strategy", "description" }

    require("codecompanion.utils.ui").selector(items, {
      prompt = opts.prompt,
      format = function(item)
        local formatted_item = {}
        for _, column in ipairs(opts.columns) do
          table.insert(formatted_item, item[column] or "")
        end
        return formatted_item
      end,
      callback = callback,
    })
  end

  local function selection(item)
    if item.picker and type(item.picker.items) == "table" then
      local picker_opts = {
        prompt = item.picker.prompt,
        columns = item.picker.columns,
      }
      picker(item.picker.items, picker_opts, selection)
    else
      local Strategy = require("codecompanion.strategy")
      return Strategy.new({
        client = client,
        context = context,
        selected = item,
      }):start(item.strategy)
    end
  end

  --TODO: Consider merging in the config file
  local items = require("codecompanion.actions").static.actions

  picker(
    items,
    { prompt = "Select an action", columns = { "name", "strategy", "description" } },
    selection
  )
end

M.setup = function()
  config.setup()
end

return M
