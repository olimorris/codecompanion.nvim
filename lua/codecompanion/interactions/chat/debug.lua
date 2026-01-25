local buf_utils = require("codecompanion.utils.buffers")
local config = require("codecompanion.config")
local helpers = require("codecompanion.interactions.chat.helpers")
local ui_utils = require("codecompanion.utils.ui")
local utils = require("codecompanion.utils")

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

  local bufname
  if _G.codecompanion_current_context and api.nvim_buf_is_valid(_G.codecompanion_current_context) then
    bufname = buf_utils.name_from_bufnr(_G.codecompanion_current_context)
  end

  -- Get the current settings from the chat buffer rather than making new ones
  local current_settings = self.settings or {}

  if adapter.schema and adapter.schema.model then
    if type(adapter.schema.model.choices) == "function" then
      models = adapter.schema.model.choices(adapter, { async = false })
    else
      models = adapter.schema.model.choices
    end
  end

  local lines = {}

  table.insert(lines, '-- Adapter: "' .. adapter.formatted_name .. '"')
  if adapter.type == "acp" then
    local command
    if adapter.commands and adapter.commands.selected then
      command = adapter.commands.selected
    else
      command = adapter.commands.default
    end
    table.insert(lines, '-- With Command: "' .. table.concat(command, " ") .. '"')

    if self.chat.acp_connection then
      -- Show current model if available
      local acp_models = self.chat.acp_connection:get_models()
      if acp_models and acp_models.currentModelId then
        local model = acp_models.currentModelId
        for _, m in ipairs(acp_models or {}) do
          if m.modelId == acp_models.currentModelId then
            model = m.name .. " (" .. m.modelId .. ")"
            break
          end
        end
        local models_list = vim
          .iter(acp_models.availableModels)
          :map(function(m)
            return m.modelId
          end)
          :totable()
        table.sort(models_list)
        table.insert(
          lines,
          '-- Using Model: "' .. model .. '" (Available models: ' .. table.concat(models_list, ", ") .. ")"
        )
      end

      -- Show current mode if available
      local modes = self.chat.acp_connection:get_modes()
      if modes and modes.currentModeId then
        local mode_name = modes.currentModeId
        for _, mode in ipairs(modes.availableModes or {}) do
          if mode.id == modes.currentModeId then
            mode_name = mode.name .. " (" .. mode.id .. ")"
            break
          end
        end
        table.insert(lines, '-- Mode: "' .. mode_name .. '"')
      end
    end
  end
  table.insert(lines, "-- Buffer Number: " .. self.chat.bufnr)
  if bufname then
    table.insert(lines, '-- Following Buffer: "' .. bufname .. '" (' .. _G.codecompanion_current_context .. ")")
  end

  -- Add MCP status
  local mcp_status = require("codecompanion.mcp").get_status()
  if vim.tbl_count(mcp_status) > 0 then
    table.insert(lines, "")
    table.insert(lines, "-- MCP Servers:")
    for server, status in pairs(mcp_status) do
      local is_ready = status.ready and " " or " "
      table.insert(lines, string.format("--   %s%s (tools: %d)", is_ready, server, status.tool_count))
    end
  end

  -- Add settings
  if not config.display.chat.show_settings and adapter.type ~= "acp" then
    table.insert(lines, "")
    local keys = {}

    -- Collect all settings keys including those with nil defaults
    if self.settings then
      for key, _ in pairs(self.settings) do
        table.insert(keys, key)
      end
    end

    -- Add any schema keys that have an explicit nil default
    if adapter.schema then
      for key, schema_value in pairs(adapter.schema) do
        if schema_value.default == nil and not vim.tbl_contains(keys, key) then
          table.insert(keys, key)
        end
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

    if vim.tbl_count(keys) == 0 then
      table.insert(lines, "-- No settings available")
    else
      table.insert(lines, "local settings = {")
      for _, key in ipairs(keys) do
        local val = self.settings[key]
        local is_nil = adapter.schema[key] and adapter.schema[key].default == nil

        local formatted_key = key
        if key:find("%.") then
          formatted_key = '["' .. key .. '"]'
        end

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
            table.insert(lines, "  " .. formatted_key .. ' = "' .. val .. '", ' .. other_models)
          else
            table.insert(lines, "  " .. formatted_key .. ' = "' .. val .. '",')
          end
        elseif is_nil and current_settings[key] == nil then
          table.insert(lines, "  " .. formatted_key .. " = nil,")
        else
          if type(val) == "function" then
            val = val(self.adapter)
          end

          if type(val) == "number" or type(val) == "boolean" then
            table.insert(lines, "  " .. formatted_key .. " = " .. tostring(val) .. ",")
          elseif type(val) == "string" then
            table.insert(lines, "  " .. formatted_key .. ' = "' .. val .. '",')
          else
            local inspected = vim.inspect(val)
            local lines_to_add = vim.split(inspected, "\n")
            for i, line in ipairs(lines_to_add) do
              if i == 1 then
                table.insert(lines, "  " .. formatted_key .. " = " .. line)
              else
                table.insert(lines, "  " .. line)
              end
            end
            lines[#lines] = lines[#lines] .. ","
          end
        end
      end

      table.insert(lines, "}")
    end
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

  api.nvim_buf_set_name(self.bufnr, "CodeCompanion_debug")
  -- Set the keymaps as per the user's chat buffer config
  local maps = {}
  local config_maps = vim.deepcopy(config.interactions.chat.keymaps)
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

  ui_utils.create_float(
    lines,
    vim.tbl_extend("force", config.display.chat.floating_window, {
      bufnr = self.bufnr,
      ft = "lua",
      title = "Debug Chat",
    })
  )

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
    helpers.apply_settings_and_model(self.chat, settings)
  end
  if messages then
    self.chat.messages = messages
  end

  utils.notify("Updated the settings and messages")
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
