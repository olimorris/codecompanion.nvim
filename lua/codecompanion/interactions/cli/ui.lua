local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local shared_ui = require("codecompanion.interactions.shared.ui")
local utils = require("codecompanion.utils")

---@class CodeCompanion.CLI.UI
---@field bufnr number
---@field winnr number|nil
local UI = {}

---Resolve the window config by inheriting from display.chat.window
---and overlaying display.cli.window if present
---@return table
local function resolve_window_config()
  local window = vim.deepcopy(config.display.chat.window)
  if config.display.cli and config.display.cli.window then
    window = vim.tbl_deep_extend("force", window, config.display.cli.window)
  end
  return window
end

---@param args { bufnr: number }
---@return CodeCompanion.CLI.UI
function UI.new(args)
  local self = setmetatable({
    bufnr = args.bufnr,
    winnr = nil,
  }, { __index = UI }) ---@cast self CodeCompanion.CLI.UI

  return self
end

---Open the CLI window
---@param opts? { width?: number, height?: number }
---@return CodeCompanion.CLI.UI
function UI:open(opts)
  opts = opts or {}

  if self:is_visible() then
    return self
  end

  local window = resolve_window_config()
  if opts.width then
    window.width = opts.width
  end
  if opts.height then
    window.height = opts.height
  end

  self.winnr = shared_ui.open(self.bufnr, window, {
    title = " " .. config.display.input.title .. " ",
  })

  log:trace("CLI window opened")
  utils.fire("CLIOpened", { bufnr = self.bufnr })

  return self
end

---Hide the CLI window (does not kill the terminal process)
---@return nil
function UI:hide()
  local window = resolve_window_config()
  shared_ui.hide(self.winnr, self.bufnr, window.layout)

  utils.fire("CLIHidden", { bufnr = self.bufnr })
end

---Determine if the CLI buffer is active
---@return boolean
function UI:is_active()
  return shared_ui.is_active(self.bufnr)
end

---Determine if the CLI window is visible
---@return boolean
function UI:is_visible()
  return shared_ui.is_visible(self.winnr, self.bufnr)
end

---CLI window is visible but not in the current tab
---@return boolean
function UI:is_visible_non_curtab()
  return shared_ui.is_visible_non_curtab(self.winnr, self.bufnr)
end

return UI
