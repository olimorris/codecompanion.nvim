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
local function get_title(opts)
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
function M.get_title_line(ui)
  if config.display.chat.title.position ~= "buffer" then
    return nil
  end

  local title = get_title({ chat_bufnr = ui.chat_bufnr, position = "buffer" })
  return title and ("# " .. title) or nil
end

---Add the H1 to lines bound for the chat buffer, beneath any settings, returning its 0-based row
---@param ui CodeCompanion.Chat.UI
---@param opts { lines: string[] }
---@return number|nil
function M.add_title_line(ui, opts)
  local title_line = M.get_title_line(ui)
  if not title_line then
    return nil
  end

  local row = 0
  if opts.lines[1] == "---" then
    for index = 2, #opts.lines do
      if opts.lines[index] == "---" then
        row = opts.lines[index + 1] == "" and index + 1 or index
        break
      end
    end
  end

  table.insert(opts.lines, row + 1, title_line)
  table.insert(opts.lines, row + 2, "")
  return row
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
---@return number|nil
local function get_title_row(ui)
  local mark = api.nvim_buf_get_extmark_by_id(ui.chat_bufnr, NS_ROW, ROW_MARK, { details = true })
  if mark[1] and not mark[3].invalid then
    return mark[1]
  end
end

---Take the H1 out of the chat buffer's lines, so a restored session can add it afresh
---@param ui CodeCompanion.Chat.UI
---@param opts { lines: string[] }
---@return string[]
function M.remove_title_line(ui, opts)
  local row = get_title_row(ui)
  if row then
    table.remove(opts.lines, row + 1)
    if opts.lines[row + 1] == "" then
      table.remove(opts.lines, row + 1)
    end
  end
  return opts.lines
end

---@param ui CodeCompanion.Chat.UI
---@return nil
local function rewrite_title_line(ui)
  local row = get_title_row(ui)
  local title_line = M.get_title_line(ui)
  if not row or not title_line then
    return
  end

  local current = api.nvim_buf_get_lines(ui.chat_bufnr, row, row + 1, false)[1]
  if current ~= title_line then
    local buffer = vim.bo[ui.chat_bufnr]
    local modifiable, modified = buffer.modifiable, buffer.modified
    buffer.modifiable = true
    api.nvim_buf_set_text(ui.chat_bufnr, row, 0, row, #current, { title_line })
    buffer.modifiable, buffer.modified = modifiable, modified
  end
end

---Show the title in the winbar of the chat's window
---@param ui CodeCompanion.Chat.UI
---@return nil
function M.set(ui)
  if config.display.chat.title.position == "winbar" then
    -- Scoped to the chat buffer, so another buffer opened in the window doesn't inherit the chat's title
    vim.wo[ui.winnr][0].winbar = get_expression(ui.chat_bufnr)
  end
end

---Neovim doesn't re-evaluate the winbar when the metadata it reads changes
---@param ui CodeCompanion.Chat.UI
---@return nil
function M.refresh(ui)
  local position = config.display.chat.title.position
  if position == "buffer" then
    return rewrite_title_line(ui)
  end
  if position == "winbar" and ui:is_visible() and vim.wo[ui.winnr].winbar == get_expression(ui.chat_bufnr) then
    api.nvim__redraw({ win = ui.winnr, winbar = true })
  end
end

---@param chat_bufnr number
---@return string
function M.render(chat_bufnr)
  return get_title({ chat_bufnr = chat_bufnr, position = "winbar" }) or ""
end

return M
