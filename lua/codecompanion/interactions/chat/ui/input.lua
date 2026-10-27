local config = require("codecompanion.config")
local ui_utils = require("codecompanion.utils.ui")

local api = vim.api

local CONTEXT_HEADER = require("codecompanion.interactions.chat.context").HEADER

---@class CodeCompanion.Chat.UI.Input
---@field bufnr number
---@field height number
---@field on_closed fun() Called when the user closes the input window themselves
---@field winnr? number
---@field _hiding? boolean
local Input = {}

---@param args { chat_bufnr: number, on_closed: fun() }
---@return CodeCompanion.Chat.UI.Input
function Input.new(args)
  local bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(bufnr, string.format("[CodeCompanion] %d input", args.chat_bufnr))

  if config.interactions.chat.opts.completion_provider == "default" then
    vim.bo[bufnr].omnifunc = "v:lua.require'codecompanion.providers.completion.default.omnifunc'.omnifunc"
  end

  return setmetatable({
    bufnr = bufnr,
    height = config.display.chat.input.height,
    on_closed = args.on_closed,
  }, { __index = Input }) ---@type CodeCompanion.Chat.UI.Input
end

---@return boolean
function Input:is_visible()
  return self.winnr ~= nil and api.nvim_win_is_valid(self.winnr) and api.nvim_win_get_buf(self.winnr) == self.bufnr
end

---Open the input in a split beneath the chat window and move the cursor into it
---@param opts { chat_winnr: number }
---@return nil
function Input:open(opts)
  if not self:is_visible() then
    self.winnr = api.nvim_open_win(self.bufnr, true, { split = "below", win = opts.chat_winnr, height = self.height })
    ui_utils.set_win_options(
      self.winnr,
      vim.tbl_extend("force", config.display.chat.window.opts, { winfixheight = true })
    )
    -- Set after the window is current, as the syntax highlighting autocmds act on the current buffer
    vim.bo[self.bufnr].filetype = "codecompanion_chat_input"
    pcall(vim.treesitter.start, self.bufnr, "markdown")
    require("codecompanion.interactions.chat.ui.folds"):setup(self.winnr)
    self:_fold_context()

    api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(self.winnr),
      once = true,
      callback = function()
        self:_remember_height()
        if not self._hiding then
          vim.schedule(self.on_closed)
        end
      end,
    })
  end

  api.nvim_set_current_win(self.winnr)
end

---Close the input window, keeping the buffer for when the chat is next shown
---@return nil
function Input:hide()
  if not self:is_visible() then
    return
  end

  self._hiding = true
  self:_remember_height()
  pcall(api.nvim_win_close, self.winnr, true)
  self._hiding = false
  self.winnr = nil
end

---Delete the input buffer, which also closes its window
---@return nil
function Input:close()
  self._hiding = true
  pcall(api.nvim_buf_delete, self.bufnr, { force = true })
  self.winnr = nil
end

---Move the cursor to the end of the input and enter insert mode
---@return nil
function Input:focus()
  if not self:is_visible() then
    return
  end

  api.nvim_set_current_win(self.winnr)
  local last_line = api.nvim_buf_line_count(self.bufnr)
  api.nvim_win_set_cursor(self.winnr, { last_line, 0 })
  vim.cmd("startinsert!")
end

---@return string[]
function Input:get_lines()
  return api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
end

---The number of lines at the top of the input taken up by the context block and the blank line beneath it
---@return number
function Input:_context_length()
  local lines = self:get_lines()
  if lines[1] ~= CONTEXT_HEADER then
    return 0
  end

  local length = 1
  while lines[length + 1] and vim.startswith(lines[length + 1], ">") do
    length = length + 1
  end
  if lines[length + 1] == "" then
    length = length + 1
  end

  return length
end

---The context items listed in the context block
---@return string[]
function Input:get_context()
  return vim.tbl_filter(function(line)
    return vim.startswith(line, "> - ")
  end, api.nvim_buf_get_lines(self.bufnr, 0, self:_context_length(), false))
end

---The text the user has written, without the context block
---@return string
function Input:get_prompt()
  local lines = api.nvim_buf_get_lines(self.bufnr, self:_context_length(), -1, false)
  return vim.trim(table.concat(lines, "\n"))
end

---Remove everything the user has written, keeping the context block
---@return nil
function Input:clear_prompt()
  local length = self:_context_length()
  -- Leave a line to write on beneath the blank line that separates it from the context block
  api.nvim_buf_set_lines(self.bufnr, length, -1, false, length > 0 and { "" } or {})
  if self:is_visible() then
    api.nvim_win_set_cursor(self.winnr, { api.nvim_buf_line_count(self.bufnr), 0 })
  end
end

---@return nil
function Input:clear()
  api.nvim_buf_set_lines(self.bufnr, 0, -1, false, {})
end

---Add text after anything the user has already written
---@param content string
---@return nil
function Input:add_prompt(content)
  local lines = vim.split(content, "\n", { plain = true })
  if self:get_prompt() == "" then
    api.nvim_buf_set_lines(self.bufnr, self:_context_length(), -1, false, lines)
  else
    api.nvim_buf_set_lines(self.bufnr, -1, -1, false, lines)
  end
end

---Add text above anything the user has already written, beneath the context block
---@param content string
---@return nil
function Input:prepend_prompt(content)
  local lines = vim.split(content, "\n", { plain = true })
  if self:get_prompt() ~= "" then
    table.insert(lines, "")
  end

  local row = self:_context_length()
  api.nvim_buf_set_lines(self.bufnr, row, row, false, lines)
end

---Replace the context block at the top of the input
---@param lines string[] The context lines, including the header, or empty to remove the block
---@return nil
function Input:set_context(lines)
  lines = vim.deepcopy(lines)
  if #lines > 0 then
    table.insert(lines, "")
  end

  local is_empty = self:get_prompt() == ""
  api.nvim_buf_set_lines(self.bufnr, 0, self:_context_length(), false, lines)
  if is_empty then
    api.nvim_buf_set_lines(self.bufnr, self:_context_length(), -1, false, #lines > 0 and { "" } or {})
  end
  self:_fold_context()
end

---Add a single context item to the context block, creating the block if needed
---@param line string
---@return nil
function Input:add_context(line)
  local length = self:_context_length()
  if length == 0 then
    return self:set_context({ CONTEXT_HEADER, line })
  end

  local lines = self:get_lines()
  local row = lines[length] == "" and length - 1 or length
  api.nvim_buf_set_lines(self.bufnr, row, row, false, { line })
  self:_fold_context()
end

---Fold the context items, leaving the header visible so it's clear what has been folded
---@return nil
function Input:_fold_context()
  local items = #self:get_context()
  if items == 0 or not self:is_visible() then
    return
  end

  api.nvim_win_call(self.winnr, function()
    require("codecompanion.interactions.chat.ui.folds"):create_context_fold(
      self.bufnr,
      1,
      items,
      string.format("> %d items folded", items)
    )
  end)
end

---@return nil
function Input:_remember_height()
  local ok, height = pcall(api.nvim_win_get_height, self.winnr)
  if ok then
    self.height = height
  end
end

return Input
