local ui_utils = require("codecompanion.utils.ui")

local api = vim.api

local M = {}

---@return number
local function rows()
  return vim.o.lines
end

---@return number
local function cols()
  return vim.o.columns
end

---Resolve dimension values (function, string, fraction, absolute, { min, max } table)
---@param window table The window config table
---@return number height
---@return number width
function M.resolve_dimensions(window)
  local function resolve(value, total)
    if type(value) == "function" then
      value = value()
    end
    if type(value) == "string" then
      return total
    end
    if type(value) == "table" then
      local min = value.min or 0
      local max = value.max or 1

      -- Resolve fractions (0 < v < 1) to absolute values
      local resolved_min = min > 0 and min < 1 and math.floor(total * min) or min
      local resolved_max = max > 0 and max < 1 and math.floor(total * max) or max

      -- Clamp: at least min, at most max
      return math.max(resolved_min, math.min(resolved_max, total))
    end
    return value >= 1 and value or math.floor(total * value)
  end

  return resolve(window.height, rows()), resolve(window.width, cols())
end

---Open a window with the given layout and place a buffer in it
---@param bufnr number The buffer to display
---@param window table The window config (layout, position, width, height, etc.)
---@param opts? { title?: string, filetype?: string }
---@return number winnr The created window number
function M.open(bufnr, window, opts)
  opts = opts or {}

  local height, width = M.resolve_dimensions(window)
  local winnr

  if window.layout == "float" then
    local title = opts.title or " CodeCompanion "

    local win_opts = {
      relative = window.relative,
      width = width,
      height = height,
      col = window.col or math.floor((cols() - width) / 2),
      row = window.row or math.floor((rows() - height) / 2),
      border = window.border,
      title = title,
      title_pos = window.title_pos or "center",
      zindex = 45,
    }
    winnr = api.nvim_open_win(bufnr, true, win_opts)
  elseif window.layout == "vertical" then
    local position = window.position
    if position == nil or (position ~= "left" and position ~= "right") then
      position = vim.opt.splitright:get() and "right" or "left"
    end
    if window.full_height then
      if position == "left" then
        vim.cmd("topleft vsplit")
      else
        vim.cmd("botright vsplit")
      end
    else
      vim.cmd("vsplit")
    end
    if position == "left" and vim.opt.splitright:get() then
      vim.cmd("wincmd h")
    end
    if position == "right" and not vim.opt.splitright:get() then
      vim.cmd("wincmd l")
    end
    if (window.width or 0) > 0 then
      vim.cmd("vertical resize " .. width)
    end
    winnr = api.nvim_get_current_win()
    api.nvim_win_set_buf(winnr, bufnr)
  elseif window.layout == "horizontal" then
    local position = window.position
    if position == nil or (position ~= "top" and position ~= "bottom") then
      position = vim.opt.splitbelow:get() and "bottom" or "top"
    end
    vim.cmd("split")
    if position == "top" and vim.opt.splitbelow:get() then
      vim.cmd("wincmd k")
    end
    if position == "bottom" and not vim.opt.splitbelow:get() then
      vim.cmd("wincmd j")
    end
    if (window.height or 0) > 0 then
      vim.cmd("resize " .. height)
    end
    winnr = api.nvim_get_current_win()
    api.nvim_win_set_buf(winnr, bufnr)
  elseif window.layout == "tab" then
    vim.cmd("tabnew")
    winnr = api.nvim_get_current_win()
    api.nvim_win_set_buf(winnr, bufnr)
  else
    winnr = api.nvim_get_current_win()
    api.nvim_set_current_buf(bufnr)
  end

  if window.opts and not vim.tbl_isempty(window.opts) then
    ui_utils.set_win_options(winnr, window.opts)
  end
  if opts.filetype then
    api.nvim_set_option_value("filetype", opts.filetype, { buf = bufnr })
  end

  return winnr
end

---Hide a window based on layout type
---@param winnr number|nil The window to hide
---@param bufnr number The buffer in the window
---@param layout string The layout type
---@return nil
function M.hide(winnr, bufnr, layout)
  if layout == "float" or layout == "vertical" or layout == "horizontal" then
    if api.nvim_get_current_buf() == bufnr then
      vim.cmd("hide")
    else
      if not winnr then
        winnr = ui_utils.buf_get_win(bufnr)
      end
      if winnr then
        api.nvim_win_hide(winnr)
      end
    end
  elseif layout == "tab" then
    vim.cmd("tabprevious")
  else
    vim.cmd("buffer " .. vim.fn.bufnr("#"))
  end
end

---Check if a buffer is the current buffer
---@param bufnr number
---@return boolean
function M.is_active(bufnr)
  return api.nvim_get_current_buf() == bufnr
end

---Check if a window is visible and showing the given buffer
---@param winnr number|nil
---@param bufnr number
---@return boolean
function M.is_visible(winnr, bufnr)
  if not winnr then
    return false
  end
  return api.nvim_win_is_valid(winnr) and api.nvim_win_get_buf(winnr) == bufnr
end

---Check if a window is visible but not in the current tab
---@param winnr number|nil
---@param bufnr number
---@return boolean
function M.is_visible_non_curtab(winnr, bufnr)
  if not winnr then
    return false
  end
  return M.is_visible(winnr, bufnr) and api.nvim_get_current_tabpage() ~= api.nvim_win_get_tabpage(winnr)
end

return M
