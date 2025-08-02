local buf_utils = require("codecompanion.utils.buffers")
local config = require("codecompanion.config")
local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils")

local api = vim.api

---@param bufnr number
---@param opts? table
local function _get_settings_key(bufnr, opts)
  opts = vim.tbl_extend("force", opts or {}, {
    lang = "lua",
  })
  local node = vim.treesitter.get_node(opts)

  local current = node
  local in_settings = false
  while current do
    if current:type() == "assignment_statement" then
      local name_node = current:named_child(0)
      if name_node and vim.treesitter.get_node_text(name_node, bufnr) == "settings" then
        in_settings = true
        break
      end
    end
    current = current:parent()
  end

  if not in_settings then
    return
  end

  while node do
    if node:type() == "field" then
      local key_node = node:named_child(0)
      if key_node and key_node:type() == "identifier" then
        local key_name = vim.treesitter.get_node_text(key_node, bufnr)
        return key_name, node
      end
    end
    node = node:parent()
  end
end

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
  self.adapter = adapter

  local bufname = buf_utils.name_from_bufnr(self.chat.buffer_context.bufnr)

  -- Get the current settings from the chat buffer rather than making new ones
  local current_settings = self.settings or {}

  if type(adapter.schema.model.choices) == "function" then
    models = adapter.schema.model.choices(adapter)
  else
    models = adapter.schema.model.choices
  end

  local lines = {}

  table.insert(lines, '-- Adapter: "' .. adapter.formatted_name .. '"')
  table.insert(lines, "-- Buffer Number: " .. self.chat.bufnr)
  table.insert(lines, '-- Current Context: "' .. bufname .. '" (' .. self.chat.buffer_context.bufnr .. ")")

  -- Add settings
  if not config.display.chat.show_settings then
    table.insert(lines, "")
    local keys = {}

    -- Collect all settings keys including those with nil defaults
    for key, _ in pairs(self.settings) do
      table.insert(keys, key)
    end

    -- Add any schema keys that have an explicit nil default
    for key, schema_value in pairs(adapter.schema) do
      if schema_value.default == nil and not vim.tbl_contains(keys, key) then
        table.insert(keys, key)
      end
    end

    table.sort(keys, function(a, b)
      local a_order = adapter.schema[a] and adapter.schema[a].order or 999
      local b_order = adapter.schema[b] and adapter.schema[b].order or 999
      if a_order == b_order then
        return a < b -- alphabetical sort as fallback
      end
      return a_order < b_order
    end)

    table.insert(lines, "local settings = {")
    for _, key in ipairs(keys) do
      local val = self.settings[key]
      local is_nil = adapter.schema[key] and adapter.schema[key].default == nil

      if key == "model" then
        local other_models = " -- "

        vim.iter(models):each(function(model, model_name)
          if type(model) == "number" then
            model = model_name
          end
          if model ~= val then
            other_models = other_models .. '"' .. model .. '", '
          end
        end)

        if type(val) == "function" then
          val = val(self.adapter)
        end
        if vim.tbl_count(models) > 1 then
          table.insert(lines, "  " .. key .. ' = "' .. val .. '", ' .. other_models)
        else
          table.insert(lines, "  " .. key .. ' = "' .. val .. '",')
        end
      elseif is_nil and current_settings[key] == nil then
        table.insert(lines, "  " .. key .. " = nil,")
      elseif type(val) == "number" or type(val) == "boolean" then
        table.insert(lines, "  " .. key .. " = " .. tostring(val) .. ",")
      elseif type(val) == "string" then
        table.insert(lines, "  " .. key .. ' = "' .. val .. '",')
      elseif type(val) == "function" then
        local expanded_val = val(self.adapter)
        if type(expanded_val) == "number" or type(expanded_val) == "boolean" then
          table.insert(lines, "  " .. key .. " = " .. tostring(val(self.adapter)) .. ",")
        else
          table.insert(lines, "  " .. key .. ' = "' .. tostring(val(self.adapter)) .. '",')
        end
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

  local window = vim.deepcopy(config.display.chat.window)
  if type(config.display.chat.debug_window.height) == "function" then
    window.height = config.display.chat.debug_window.height()
  else
    window.height = config.display.chat.debug_window.height
  end
  if type(config.display.chat.debug_window.width) == "function" then
    window.width = config.display.chat.debug_window.width()
  else
    window.width = config.display.chat.debug_window.width
  end

  ui.create_float(lines, {
    bufnr = self.bufnr,
    filetype = "lua",
    relative = "editor",
    title = "Debug Chat",
    window = window,
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

  api.nvim_create_autocmd("CursorMoved", {
    group = self.aug,
    buffer = self.bufnr,
    desc = "Show settings information in the CodeCompanion chat buffer",
    callback = function()
      local key_name, node = _get_settings_key(self.bufnr)
      if not key_name or not node then
        return vim.diagnostic.set(config.INFO_NS, self.bufnr, {})
      end

      local key_schema = self.adapter.schema[key_name]
      if key_schema and key_schema.desc then
        local lnum, col, end_lnum, end_col = node:range()
        local diagnostic = {
          lnum = lnum,
          col = col,
          end_lnum = end_lnum,
          end_col = end_col,
          severity = vim.diagnostic.severity.INFO,
          message = key_schema.desc,
        }
        vim.diagnostic.set(config.INFO_NS, self.bufnr, { diagnostic })
      end
    end,
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
