local adapter_ui = require("codecompanion.adapters.ui")
local config = require("codecompanion.config")
local utils = require("codecompanion.utils")

local M = {}

---Update the system prompt after adapter change
---@param chat CodeCompanion.Chat
function M.update_system_prompt(chat)
  local system_prompt = config.interactions.chat.opts.system_prompt
  if type(system_prompt) == "function" then
    if chat.messages[1] and chat.messages[1].role == "system" then
      chat.messages[1].content = system_prompt(chat:make_system_prompt_context())
    end
  end
end

---@param chat CodeCompanion.Chat
---@return nil
local function select_model(chat)
  adapter_ui.select_model({
    adapter = chat.adapter,
    acp_models = chat.adapter.type == "acp" and chat.acp_connection:get_models() or nil,
    on_choice = function(model_id)
      if model_id then
        chat:change_model({ model = model_id })
      end
    end,
  })
end

---Main callback for the change_adapter keymap
---@param chat CodeCompanion.Chat
---@return nil
function M.callback(chat)
  if config.display.chat.show_settings then
    return utils.notify("Adapter can't be changed when `display.chat.show_settings = true`", vim.log.levels.WARN)
  end

  local current_adapter = chat.adapter.name

  adapter_ui.select_adapter({
    current = current_adapter,
    on_choice = function(selected_adapter)
      if not selected_adapter then
        return
      end

      local function on_adapter_ready()
        -- Only force a system prompt update if the user isn't ignoring it. This
        -- occurs when a user has initiated a chat from the prompt library
        if not chat.opts.ignore_system_prompt then
          M.update_system_prompt(chat)
        end

        return select_model(chat)
      end

      if current_adapter ~= selected_adapter then
        chat:change_adapter({ adapter = selected_adapter, callback = on_adapter_ready })
      else
        return on_adapter_ready()
      end
    end,
  })
end

return M
