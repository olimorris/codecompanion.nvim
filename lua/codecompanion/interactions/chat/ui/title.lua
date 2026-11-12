local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local api = vim.api

local NS_ROW = api.nvim_create_namespace("CodeCompanion-title")
local ROW_MARK = 1

local M = {}

---@param chat_bufnr number
---@return string
local function get_expression(chat_bufnr)
  return string.format("%%{%%v:lua.require'codecompanion.interactions.chat.ui.title'.render(%d)%%}", chat_bufnr)
end

---@param opts { chat_bufnr: number, position: "winbar"|"buffer" }
---@return string|nil
local function get_text(opts)
  local metadata = _G.codecompanion_chat_metadata[opts.chat_bufnr]
  if not metadata then
    return nil
  end

  local ok, result = pcall(config.display.chat.title.text[opts.position], metadata)
  if not ok then
    log:error("[Chat] Failed to build the title: %s", result)
    return nil
  end
  return result
end

---The H1 for the top of the chat buffer, when the title is shown there
---@param ui CodeCompanion.Chat.UI
---@return string|nil
function M.get_line(ui)
  if config.display.chat.title.position ~= "buffer" then
    return nil
  end
  local text = get_text({ chat_bufnr = ui.chat_bufnr, position = "buffer" })
  return text and ("# " .. text) or nil
end

---Mark the H1 once it's been written, so a new title can replace it in place
---@param ui CodeCompanion.Chat.UI
---@param opts { row: number }
---@return nil
function M.mark(ui, opts)
  api.nvim_buf_set_extmark(
    ui.chat_bufnr,
    NS_ROW,
    opts.row,
    0,
    { id = ROW_MARK, invalidate = true, undo_restore = false }
  )
end

---@param ui CodeCompanion.Chat.UI
---@return nil
local function rewrite(ui)
  local mark = api.nvim_buf_get_extmark_by_id(ui.chat_bufnr, NS_ROW, ROW_MARK, { details = true })
  local line = M.get_line(ui)
  if not mark[1] or mark[3].invalid or not line then
    return
  end

  local row = mark[1]
  local current = api.nvim_buf_get_lines(ui.chat_bufnr, row, row + 1, false)[1]
  if current ~= line then
    local buffer = vim.bo[ui.chat_bufnr]
    local modifiable, modified = buffer.modifiable, buffer.modified
    buffer.modifiable = true
    api.nvim_buf_set_text(ui.chat_bufnr, row, 0, row, #current, { line })
    buffer.modifiable, buffer.modified = modifiable, modified
  end
end

---Show the title in the winbar of the chat's window
---@param ui CodeCompanion.Chat.UI
---@return nil
function M.set(ui)
  if config.display.chat.title.position == "winbar" then
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

---Neovim doesn't re-evaluate the winbar when the metadata it reads changes
---@param ui CodeCompanion.Chat.UI
---@return nil
function M.refresh(ui)
  local position = config.display.chat.title.position
  if position == "buffer" then
    return rewrite(ui)
  end
  if position == "winbar" and ui:is_visible() and vim.wo[ui.winnr].winbar == get_expression(ui.chat_bufnr) then
    api.nvim__redraw({ win = ui.winnr, winbar = true })
  end
end

---@param chat_bufnr number
---@return string
function M.render(chat_bufnr)
  return get_text({ chat_bufnr = chat_bufnr, position = "winbar" }) or ""
end

return M
