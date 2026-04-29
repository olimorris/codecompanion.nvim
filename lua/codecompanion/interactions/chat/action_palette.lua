local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local slash_command_filter = require("codecompanion.interactions.chat.slash_commands.filter")

---@class CodeCompanion.Chat.CommandPalette
local CommandPalette = {}

---Format a keymap's modes into a single display string
---@param modes table<string, string|string[]>
---@return string
local function format_keys(modes)
  local order = { "n", "i" }
  local segments = {}

  for _, mode in ipairs(order) do
    local key = modes[mode]
    if key then
      local keys = type(key) == "table" and key or { key }
      table.insert(segments, mode .. ": " .. table.concat(keys, ", "))
    end
  end

  return table.concat(segments, "  ")
end

---Build the static items shown in every chat command palette
---@return table
local function static_items()
  return {
    {
      callback = function()
        require("codecompanion").actions()
      end,
      description = "Open the action palette",
      name = "CodeCompanion actions",
      type = "static",
    },
  }
end

---Build items from the chat's keymaps
---@param chat CodeCompanion.Chat
---@return table
local function keymap_items(chat)
  local items = {}
  local keymaps = config.interactions.chat.keymaps

  for name, map in pairs(keymaps) do
    if name:sub(1, 1) == "_" or map.hide then
      goto continue
    end

    if type(map.condition) == "function" and not map.condition() then
      goto continue
    end

    if map.opts and map.opts.chat and map.opts.chat.show_in_action_palette == false then
      goto continue
    end

    table.insert(items, {
      callback = function()
        local callback_path = map.callback
        if type(callback_path) == "string" then
          local module_name, fn_name = callback_path:match("^(.+)%.(.+)$")
          if module_name and fn_name then
            local mod = require("codecompanion.interactions.chat." .. module_name)
            if mod[fn_name] and mod[fn_name].callback then
              return mod[fn_name].callback(chat)
            end
          end
        end
      end,
      description = format_keys(map.modes or {}),
      index = map.index or 99,
      name = map.description or name,
      type = "keymap",
    })

    ::continue::
  end

  table.sort(items, function(a, b)
    return a.index < b.index
  end)

  return items
end

---Build items from the chat's slash commands
---@param chat CodeCompanion.Chat
---@return table
local function slash_command_items(chat)
  local items = {}
  local slash_commands = config.interactions.chat.slash_commands

  local filtered = slash_command_filter.filter_enabled_slash_commands(slash_commands, { adapter = chat.adapter })

  for name, cmd_config in pairs(filtered) do
    if name == "opts" then
      goto continue
    end

    -- Filter out CLI-only slash commands
    local allowed = cmd_config.opts and cmd_config.opts.interactions
    if allowed and not vim.tbl_contains(allowed, "chat") then
      goto continue
    end

    table.insert(items, {
      callback = function()
        local slash_commands_module = require("codecompanion.interactions.chat.slash_commands")
        slash_commands_module.new():execute({
          config = cmd_config,
          context = chat.buffer_context,
          label = "/" .. name,
        }, chat)
      end,
      description = cmd_config.description or "",
      name = "/" .. name,
      type = "slash_command",
    })

    ::continue::
  end

  table.sort(items, function(a, b)
    return a.name < b.name
  end)

  return items
end

---Launch the chat command palette
---@param chat CodeCompanion.Chat
---@return nil
function CommandPalette.launch(chat)
  local items = {}

  vim.list_extend(items, static_items())
  vim.list_extend(items, keymap_items(chat))
  vim.list_extend(items, slash_command_items(chat))

  if #items == 0 then
    return log:warn("No commands available")
  end

  local context = require("codecompanion.utils.context").get(chat.bufnr)

  return require("codecompanion.action_palette").launch_picker(items, {
    columns = { "name", "description" },
    context = context,
    title = "Chat actions",
  })
end

return CommandPalette
