local config = require("codecompanion.config")
local ui = require("codecompanion.interactions.shared.ui")

local api = vim.api

local HISTORY_MAX = 20

local M = {}

---@class CodeCompanion.Input
---@field aug number|nil
---@field bufnr number
---@field on_submit fun(text: string, submit_opts: { bang: boolean })|nil
---@field winnr number|nil

local _input = nil ---@type CodeCompanion.Input|nil
local _history = {} ---@type string[]
local _history_index = 0
local _draft = ""

---Show the input window as a float
---@param opts { title?: string }
---@return number winnr
local function _show(opts)
  if not _input then
    return 0
  end

  local window = vim.deepcopy(config.display.input.window)
  window.layout = "float"

  local winnr = ui.open(_input.bufnr, window, {
    title = opts.title or " CodeCompanion ",
    filetype = "codecompanion_input",
  })

  _input.winnr = winnr

  return winnr
end

---Submit the input buffer content and clear it
---@param opts? { bang: boolean }
local function _buf_send(opts)
  if not _input or not api.nvim_buf_is_valid(_input.bufnr) then
    return
  end

  local lines = api.nvim_buf_get_lines(_input.bufnr, 0, -1, false)
  local text = vim.trim(table.concat(lines, "\n"))
  if text == "" then
    return
  end

  -- Add to history
  table.insert(_history, text)
  if #_history > HISTORY_MAX then
    table.remove(_history, 1)
  end
  _history_index = 0
  _draft = ""

  -- Clear the buffer content and hide the window
  api.nvim_buf_set_lines(_input.bufnr, 0, -1, false, { "" })
  vim.bo[_input.bufnr].modified = false
  M.hide()

  if _input.on_submit then
    _input.on_submit(text, opts or {})
  end
end

---Set the input buffer content
---@param text string
local function _set_content(text)
  if not _input or not api.nvim_buf_is_valid(_input.bufnr) then
    return
  end

  local lines = vim.split(text, "\n", { plain = true })
  api.nvim_buf_set_lines(_input.bufnr, 0, -1, false, lines)
  vim.bo[_input.bufnr].modified = false
end

---Get the current input buffer content
---@return string
local function _get_content()
  if not _input or not api.nvim_buf_is_valid(_input.bufnr) then
    return ""
  end

  local lines = api.nvim_buf_get_lines(_input.bufnr, 0, -1, false)
  return vim.trim(table.concat(lines, "\n"))
end

---Navigate to the previous history entry
local function _history_up()
  if #_history == 0 then
    return
  end

  if _history_index == 0 then
    _draft = _get_content()
  end

  _history_index = math.min(_history_index + 1, #_history)
  _set_content(_history[#_history - _history_index + 1])
end

---Navigate to the next history entry
local function _history_down()
  if _history_index == 0 then
    return
  end

  _history_index = _history_index - 1

  if _history_index == 0 then
    _set_content(_draft)
  else
    _set_content(_history[#_history - _history_index + 1])
  end
end

---Open an input buffer
---@param opts { title?: string, on_submit: fun(text: string, submit_opts: { bang: boolean }), on_open?: fun(bufnr: number, winnr: number), initial_content?: string }
---@return nil
function M.open(opts)
  -- Buffer already exists — re-show the window
  if _input and api.nvim_buf_is_valid(_input.bufnr) then
    _input.on_submit = opts.on_submit

    if M.is_visible() then
      api.nvim_set_current_win(_input.winnr)
      vim.cmd("startinsert")
      return
    end

    _show({ title = opts.title })

    -- Set initial content if explicitly provided (overwrites draft)
    if opts.initial_content and opts.initial_content ~= "" then
      local lines = vim.split(opts.initial_content, "\n", { plain = true })
      api.nvim_buf_set_lines(_input.bufnr, 0, -1, false, lines)
    end

    vim.cmd("startinsert")

    if opts.on_open then
      opts.on_open(_input.bufnr, _input.winnr)
    end

    return
  end

  -- First-time creation
  local bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(bufnr, string.format("[CodeCompanion Input] %d", bufnr))
  vim.bo[bufnr].buftype = "acwrite"

  local completion_provider = config.interactions.chat.opts.completion_provider
  if completion_provider == "default" then
    vim.bo[bufnr].omnifunc = "v:lua.require'codecompanion.providers.completion.default.omnifunc'.omnifunc"
  end

  _input = {
    aug = nil,
    bufnr = bufnr,
    on_submit = opts.on_submit,
    winnr = nil,
  }

  _show({ title = opts.title })

  local aug = api.nvim_create_augroup("codecompanion.input." .. bufnr, { clear = true })
  api.nvim_create_autocmd("BufWriteCmd", {
    group = aug,
    buffer = bufnr,
    callback = function()
      vim.bo[bufnr].modified = false
      _buf_send({ bang = vim.v.cmdbang == 1 })
    end,
  })
  api.nvim_create_autocmd("VimLeavePre", {
    group = aug,
    callback = function()
      pcall(M.close)
    end,
  })
  _input.aug = aug

  -- Keymaps (set once, persist with the buffer)
  local callbacks = { send = _buf_send, close = M.hide, history_up = _history_up, history_down = _history_down }
  for action, keymap in pairs(config.display.input.keymaps) do
    if keymap and keymap ~= false then
      local fn = callbacks[action]
      if fn then
        for mode, keys in pairs(keymap.modes) do
          if type(keys) == "string" then
            keys = { keys }
          end
          for _, key in ipairs(keys) do
            vim.keymap.set(mode, key, fn, { buffer = bufnr, desc = "[Input] " .. keymap.description })
          end
        end
      end
    end
  end

  -- Set initial content if provided
  if opts.initial_content and opts.initial_content ~= "" then
    local lines = vim.split(opts.initial_content, "\n", { plain = true })
    api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end

  vim.cmd("startinsert")

  if opts.on_open then
    opts.on_open(bufnr, _input.winnr)
  end
end

---Hide the input window, preserving the buffer for reuse
---@return nil
function M.hide()
  if not _input then
    return
  end

  if _input.winnr and api.nvim_win_is_valid(_input.winnr) then
    api.nvim_win_close(_input.winnr, true)
  end

  if _input.bufnr and api.nvim_buf_is_valid(_input.bufnr) then
    vim.bo[_input.bufnr].modified = false
  end

  _input.winnr = nil
end

---Close the input buffer and window
---@return nil
function M.close()
  if not _input then
    return
  end

  if _input.aug then
    pcall(api.nvim_del_augroup_by_id, _input.aug)
  end

  if _input.bufnr and api.nvim_buf_is_valid(_input.bufnr) then
    vim.bo[_input.bufnr].modified = false
  end

  if _input.winnr and api.nvim_win_is_valid(_input.winnr) then
    api.nvim_win_close(_input.winnr, true)
  end

  if _input.bufnr and api.nvim_buf_is_valid(_input.bufnr) then
    api.nvim_buf_delete(_input.bufnr, { force = true })
  end

  _input = nil
end

---Check if the input window is currently visible
---@return boolean
function M.is_visible()
  return _input ~= nil and _input.winnr ~= nil and api.nvim_win_is_valid(_input.winnr)
end

---Check if the input buffer exists (even if hidden)
---@return boolean
function M.is_open()
  return _input ~= nil and api.nvim_buf_is_valid(_input.bufnr)
end

return M
