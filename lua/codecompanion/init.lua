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
        string.format("[CodeCompanion.nvim]\nCould not find env variable: %s", config.options.api_key),
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
  return require("codecompanion.strategy.chat").buf_get_chat(bufnr)
end

M.restore = function(chat, index)
  local client = get_client()
  if not client then
    return
  end

  local Chat = require("codecompanion.strategy.chat")

  Chat.new({
    client = client,
    settings = chat.settings,
    messages = chat.messages,
    type = chat.type,
  })

  _G.codecompanion_chats[index] = nil
end

M.chat = function()
  local client = get_client()
  if not client then
    return
  end

  local chat
  local Chat = require("codecompanion.strategy.chat")

  if #_G.codecompanion_chats > 0 then
    local restore = _G.codecompanion_chats[#_G.codecompanion_chats]

    chat = Chat.new({
      client = client,
      type = restore.type,
      settings = restore.settings,
      messages = restore.messages,
    })

    _G.codecompanion_chats[#_G.codecompanion_chats] = nil
  else
    chat = Chat.new({
      client = client,
    })
  end

  vim.api.nvim_win_set_buf(0, chat.bufnr)
  utils.scroll_to_end(0)
end

M.toggle = function()
  if vim.bo.filetype == "codecompanion" then
    vim.api.nvim_win_close(0, true)
  else
    M.chat()
  end
end

local _cached_actions = {}
M.actions = function()
  local client = get_client()
  if not client then
    return
  end

  local actions = require("codecompanion.actions")
  local context = utils.get_context(vim.api.nvim_get_current_buf())

  local function picker(items, opts, callback)
    opts = opts or {}
    opts.prompt = opts.prompt or "Select an option"
    opts.columns = opts.columns or { "name", "strategy", "description" }

    require("codecompanion.utils.ui").selector(items, {
      prompt = opts.prompt,
      width = config.options.display.action_palette.width,
      height = config.options.display.action_palette.height,
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
      return picker(item.picker.items, picker_opts, selection)
    elseif item.picker and type(item.picker.items) == "function" then
      local picker_opts = {
        prompt = item.picker.prompt,
        columns = item.picker.columns,
      }
      picker(item.picker.items(), picker_opts, selection)
    elseif item and type(item.callback) == "function" then
      return item.callback(selection)
    else
      local Strategy = require("codecompanion.strategy")
      return Strategy.new({
        client = client,
        context = context,
        selected = item,
      }):start(item.strategy)
    end
  end

  if not next(_cached_actions) then
    if config.options.use_default_actions then
      for _, action in ipairs(actions.static.actions) do
        table.insert(_cached_actions, action)
      end
    end
    if config.options.actions and #config.options.actions > 0 then
      for _, action in ipairs(config.options.actions) do
        table.insert(_cached_actions, action)
      end
    end
  end

  local items = actions.validate(_cached_actions, context)

  if items and #items == 0 then
    return vim.notify(
      "[CodeCompanion.nvim]\nNo actions set. Please create some in your config or turn on the defaults",
      vim.log.levels.WARN
    )
  end

  picker(items, { prompt = "Select an action", columns = { "name", "strategy", "description" } }, selection)
end

---@param opts nil|table
M.setup = function(opts)
  vim.api.nvim_set_hl(0, "CodeCompanionTokens", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "CodeCompanionVirtualText", { link = "Comment", default = true })

  config.setup(opts)
end

return M
