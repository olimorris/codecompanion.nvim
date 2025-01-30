local config = require("codecompanion.config")
local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils")

local api = vim.api

---Extract the settings and messages from the buffer
local function get_buffer_content(lines)
  local content = table.concat(lines, "\n")

  local env = {}
  local chunk, err = load(
    "local settings, messages; " .. content .. " return {settings=settings, messages=messages}",
    "buffer",
    "t",
    env
  )
  if not chunk then
    return error("Failed to parse buffer: " .. (err or "unknown error"))
  end

  local result = chunk()
  return result.settings, result.messages
end

---@class CodeCompanion.Chat.Debug
---@field chat CodeCompanion.Chat
---@field settings table
---@field aug number
local Debug = {}

function Debug.new(args)
  local self = setmetatable({
    chat = args.chat,
    settings = args.settings,
  }, { __index = Debug })

  return self
end

---Render the settings and messages
---@return CodeCompanion.Chat.Debug
function Debug:render()
  local models
  local adapter = vim.deepcopy(self.chat.adapter)

  if type(adapter.schema.model.choices) == "function" then
    models = adapter.schema.model.choices()
  else
    models = adapter.schema.model.choices
  end

  local lines = {}

  table.insert(lines, '-- Adapter: "' .. adapter.name .. '"')
  table.insert(lines, "-- Buffer: " .. self.chat.bufnr)

  -- Add settings
  if not config.display.chat.show_settings then
    table.insert(lines, "")
    table.sort(self.settings)
    table.insert(lines, "local settings = {")
    for key, val in pairs(self.settings) do
      if key == "model" then
        local other_models = " -- "

        vim.iter(models):each(function(model, model_name)
          -- Display the other models that are available in the adapter
          if type(model) == "number" then
            model = model_name
          end
          if model ~= val then
            other_models = other_models .. '"' .. model .. '", '
          end
        end)

        if type(val) == "function" then
          val = val()
        end
        if vim.tbl_count(models) > 1 then
          table.insert(lines, "  " .. key .. ' = "' .. val .. '", ' .. other_models)
        else
          table.insert(lines, "  " .. key .. ' = "' .. val .. '",')
        end
      elseif type(val) == "number" or type(val) == "boolean" then
        table.insert(lines, "  " .. key .. " = " .. val .. ",")
      elseif type(val) == "string" then
        table.insert(lines, "  " .. key .. " = " .. '"' .. val .. '",')
      else
        table.insert(lines, "  " .. key .. " = " .. vim.inspect(val))
      end
    end
    table.insert(lines, "}")
  end

  -- Add messages
  if vim.tbl_count(self.chat.messages) > 0 then
    table.insert(lines, "")
    table.insert(lines, "local messages = ")

    local messages = vim.inspect(self.chat.messages)
    for line in messages:gmatch("[^\r\n]+") do
      table.insert(lines, line)
    end
  end

  self.bufnr = api.nvim_create_buf(false, true)

  -- Set the keymaps as per the user's chat buffer config
  local maps = {}
  local config_maps = vim.deepcopy(config.strategies.chat.keymaps)
  maps["save"] = config_maps["send"]
  maps["save"].callback = "save"
  maps["save"].description = "Save debug window content"
  maps["close"] = config_maps["close"]
  maps["close"].callback = "close"
  maps["close"].description = "Close debug window"

  require("codecompanion.utils.keymaps")
    .new({
      bufnr = self.bufnr,
      callbacks = function()
        local M = {}
        M.save = function()
          return self:save()
        end
        M.close = function()
          return self:close()
        end
        return M
      end,
      data = nil,
      keymaps = maps,
    })
    :set()

  local height, width

  if type(config.display.chat.debug_window.height) == "function" then
    height = config.display.chat.debug_window.height()
  else
    height = config.display.chat.debug_window.height
  end
  if type(config.display.chat.debug_window.width) == "function" then
    width = config.display.chat.debug_window.width()
  else
    width = config.display.chat.debug_window.width
  end

  ui.create_float(lines, {
    bufnr = self.bufnr,
    filetype = "lua",
    height = height,
    ignore_keymaps = true,
    relative = "editor",
    title = "Debug Chat",
    width = width,
    window = config.display.chat.window,
    opts = {
      wrap = true,
    },
  })

  self:setup_window()

  return self
end

---Setup the debug window
---@return nil
function Debug:setup_window()
  self.aug = api.nvim_create_augroup("codecompanion.debug" .. ":" .. self.bufnr, {
    clear = true,
  })

  api.nvim_create_autocmd("BufWrite", {
    group = self.aug,
    buffer = self.bufnr,
    desc = "Save the contents of the debug window to the chat buffer",
    callback = function()
      return self:save()
    end,
  })

  api.nvim_create_autocmd({ "BufUnload", "WinClosed" }, {
    group = self.aug,
    buffer = self.bufnr,
    desc = "Clear the autocmds in the debug window",
    callback = function()
      return self:close()
    end,
  })
end

---Save the contents of the debug window to the chat buffer
function Debug:save()
  local contents = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
  local settings, messages = get_buffer_content(contents)

  if not settings and not messages then
    return
  end

  if settings then
    self.chat:apply_settings(settings)
  end
  if messages then
    self.chat.messages = messages
  end

  util.notify("Updated the settings and messages")
end

---Function to run when the debug chat is closed
---@return nil
function Debug:close()
  if self.aug then
    api.nvim_clear_autocmds({ group = self.aug })
  end
  api.nvim_buf_delete(self.bufnr, { force = true })
end

return Debug
