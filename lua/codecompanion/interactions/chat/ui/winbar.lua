local adapter_utils = require("codecompanion.adapters.utils")
local config = require("codecompanion.config")

local M = {}

---@param chat_bufnr number
---@return string
local function get_expression(chat_bufnr)
  return string.format("%%{%%v:lua.require'codecompanion.interactions.chat.ui.winbar'.render(%d)%%}", chat_bufnr)
end

---A `%` in a title would otherwise be read as the start of a statusline item
---@param text string
---@return string
local function escape(text)
  return (text:gsub("%%", "%%%%"))
end

---Show the chat's title, adapter and model in the winbar of its window
---@param ui CodeCompanion.Chat.UI
---@return nil
function M.set(ui)
  if config.display.chat.input.winbar then
    vim.wo[ui.winnr].winbar = get_expression(ui.chat_bufnr)
  end
end

---Clear the winbar, so the window doesn't keep it once it shows another buffer
---@param ui CodeCompanion.Chat.UI
---@return nil
function M.clear(ui)
  if ui:is_visible() and vim.wo[ui.winnr].winbar == get_expression(ui.chat_bufnr) then
    vim.wo[ui.winnr].winbar = ""
  end
end

---@param chat_bufnr number
---@return string
function M.render(chat_bufnr)
  local chat = require("codecompanion.interactions.chat").buf_get_chat(chat_bufnr)
  if not chat then
    return ""
  end

  local model = adapter_utils.model(chat.adapter)
  local adapter = chat.adapter.formatted_name or chat.adapter.name
  return string.format(
    "%%#CodeCompanionChatHeader# %s%%*%%=%%#Comment#%s ",
    escape(chat.title or config.display.chat.input.title),
    escape(model and string.format("%s · %s", adapter, model) or adapter)
  )
end

return M
