local config = require("codecompanion.config")
local shared_ui = require("codecompanion.interactions.shared.ui")

local api = vim.api

local M = {}

local _input = nil

---Open an input buffer
---@param opts { title?: string, on_submit: fun(text: string, submit_opts: { bang: boolean }), on_open?: fun(bufnr: number, winnr: number) }
---@return nil
function M.open(opts)
  if _input and api.nvim_buf_is_valid(_input.bufnr) then
    M.close()
  end

  local bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(bufnr, string.format("[CodeCompanion Input] %d", bufnr))
  vim.bo[bufnr].buftype = "acwrite"

  local completion_provider = config.interactions.chat.opts.completion_provider
  if completion_provider == "default" then
    vim.bo[bufnr].omnifunc = "v:lua.require'codecompanion.providers.completion.default.omnifunc'.omnifunc"
  end

  local window = vim.deepcopy(config.display.input.window)
  window.layout = "float"

  -- Set filetype after the window opens so ftplugin window-local options apply correctly
  local winnr = shared_ui.open(bufnr, window, {
    title = opts.title or " CodeCompanion ",
    filetype = "codecompanion_input",
  })

  vim.wo[winnr].wrap = true
  vim.wo[winnr].linebreak = true

  -- Send the input to the provider
  local function send(submit_opts)
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local text = vim.trim(table.concat(lines, "\n"))
    if text == "" then
      return
    end
    M.close()
    opts.on_submit(text, submit_opts or {})
  end

  local aug = api.nvim_create_augroup("codecompanion.input." .. bufnr, { clear = true })
  api.nvim_create_autocmd("BufWriteCmd", {
    group = aug,
    buffer = bufnr,
    callback = function()
      vim.bo[bufnr].modified = false
      send({ bang = vim.v.cmdbang == 1 })
    end,
  })

  -- Keymaps
  local callbacks = { send = send, close = M.close }
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

  -- Start in insert mode
  vim.cmd("startinsert")

  _input = {
    bufnr = bufnr,
    winnr = winnr,
    aug = aug,
  }

  if opts.on_open then
    opts.on_open(bufnr, winnr)
  end
end

---Close the input buffer
---@return nil
function M.close()
  if not _input then
    return
  end

  pcall(api.nvim_del_augroup_by_id, _input.aug)

  if _input.winnr and api.nvim_win_is_valid(_input.winnr) then
    api.nvim_win_close(_input.winnr, true)
  end

  if _input.bufnr and api.nvim_buf_is_valid(_input.bufnr) then
    api.nvim_buf_delete(_input.bufnr, { force = true })
  end

  _input = nil
end

---Check if the input buffer is currently open
---@return boolean
function M.is_open()
  return _input ~= nil and api.nvim_buf_is_valid(_input.bufnr)
end

return M
