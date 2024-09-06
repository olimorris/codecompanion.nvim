local config = require("codecompanion").config

local buf = require("codecompanion.utils.buffers")
local file = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

local api = vim.api

CONSTANTS = {
  NAME = "Buffer",
  PROMPT = "Select a buffer",
  DISPLAY = "name",
}

---Output from the slash command in the chat buffer
---@param SlashCommand CodeCompanion.SlashCommandBuffer
---@param selected table The selected item from the provider { name = string, bufnr = number, path = string }
---@return nil
local function output(SlashCommand, selected)
  if not config.opts.send_code and (SlashCommand.config.opts and SlashCommand.config.opts.contains_code) then
    return log:warn("Sending of code has been disabled")
  end

  -- If the buffer is not loaded, then read the file
  local content
  if not api.nvim_buf_is_loaded(selected.bufnr) then
    content = file.read(selected.path)
    if content == "" then
      return log:warn("Could not read the file: %s", selected.path)
    end
    content = "```" .. file.get_filetype(selected.path) .. "\n" .. content .. "\n```"
  else
    content = buf.format(selected.bufnr)
  end

  local Chat = SlashCommand.Chat
  Chat:append_to_buf({ content = "[!" .. CONSTANTS.NAME .. ": `" .. selected[CONSTANTS.DISPLAY] .. "`]\n" })
  Chat:append_to_buf({ content = content })
  Chat:fold_code()
end

local Providers = {
  ---The default provider
  ---@param SlashCommand CodeCompanion.SlashCommandBuffer
  ---@param list table { filetype = string, bufnr = number, name = string, path = string, relative_path = string }
  ---@return nil
  default = function(SlashCommand, list)
    vim.ui.select(list, {
      prompt = CONSTANTS.PROMPT,
      format_item = function(item)
        return item.relative_path
      end,
    }, function(selected)
      if not selected then
        return
      end

      return output(SlashCommand, selected)
    end)
  end,

  ---The Telescope provider
  ---@param SlashCommand CodeCompanion.SlashCommandBuffer
  ---@return nil
  telescope = function(SlashCommand)
    local ok, telescope = pcall(require, "telescope.builtin")
    if not ok then
      return log:error("Telescope is not installed")
    end

    telescope.buffers({
      prompt_title = CONSTANTS.PROMPT,
      attach_mappings = function(prompt_bufnr, _)
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")

        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            output(SlashCommand, {
              bufnr = selection.bufnr,
              name = selection.filename,
              path = selection.path,
            })
          end
        end)

        return true
      end,
    })
  end,
}

---@class CodeCompanion.SlashCommandBuffer
local SlashCommandBuffer = {}

---@class CodeCompanion.SlashCommandBuffer
---@field Chat CodeCompanion.Chat The chat buffer
---@field config table The config of the slash command
---@field context table The context of the chat buffer from the completion menu
function SlashCommandBuffer.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommandBuffer })

  return self
end

---Execute the slash command
---@return nil
function SlashCommandBuffer:execute()
  -- Use the `default` provider if no provider is set
  if not self.config.opts or (self.config.opts and self.config.opts.provider == "default") then
    local buffers = {}

    vim.tbl_filter(function(bufnr)
      if vim.fn.buflisted(bufnr) ~= 1 then
        return false
      end
      if api.nvim_buf_get_option(bufnr, "filetype") == "codecompanion" then
        return false
      end
      table.insert(buffers, buf.get_info(bufnr))
    end, api.nvim_list_bufs())

    if not next(buffers) then
      return log:warn("No buffers found")
    end

    -- Reorder the list so the buffer that the user initiated the chat from is at the top
    for i, buffer in ipairs(buffers) do
      if buffer.bufnr == self.Chat.context.bufnr then
        table.remove(buffers, i)
        table.insert(buffers, 1, buffer)
        break
      end
    end

    return Providers.default(self, buffers)
  elseif self.config.opts and self.config.opts.provider then
    local provider = Providers[self.config.opts.provider]
    if not provider then
      return log:error("Provider for the buffer slash command could not found: %s", self.config.opts.provider)
    end
    return provider(self)
  end
end

return SlashCommandBuffer
