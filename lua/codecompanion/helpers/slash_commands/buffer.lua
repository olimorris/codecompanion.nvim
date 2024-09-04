local config = require("codecompanion").config

local buf_utils = require("codecompanion.utils.buffers")
local log = require("codecompanion.utils.log")

local api = vim.api

CONSTANTS = {
  NAME = "Buffer",
  PROMPT = "Select a buffer",
  DISPLAY = "name",
}

---Output from the slash command in the chat buffer
---@param SlashCommand CodeCompanion.SlashCommandBuffer
---@param selected table The selected item from the provider
---@return nil
local function output(SlashCommand, selected)
  if not config.opts.send_code and (SlashCommand.config.opts and SlashCommand.config.opts.contains_code) then
    return log:warn("Sending of code has been disabled")
  end

  local Chat = SlashCommand.Chat
  Chat:append_to_buf({ content = "[!" .. CONSTANTS.NAME .. ": `" .. selected[CONSTANTS.DISPLAY] .. "`]\n" })
  Chat:append_to_buf({ content = buf_utils.format(selected.bufnr) })
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
  ---@param list table { filetype = string, bufnr = number, name = string, path = string, relative_path = string }
  ---@return nil
  telescope = function(SlashCommand, list)
    local ok, _ = pcall(require, "telescope")
    if not ok then
      return log:error("Telescope is not installed")
    end

    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local conf = require("telescope.config").values
    local finders = require("telescope.finders")
    local pickers = require("telescope.pickers")

    local select = function(opts)
      opts = opts or {}
      pickers
        .new(opts, {
          prompt_title = CONSTANTS.PROMPT,
          finder = finders.new_table({
            results = list,
            entry_maker = function(item)
              return {
                display = item.relative_path,
                ordinal = item.relative_path,
                value = item,
              }
            end,
          }),
          sorter = conf.generic_sorter(opts),
          attach_mappings = function(prompt_bufnr, _)
            actions.select_default:replace(function()
              actions.close(prompt_bufnr)
              output(SlashCommand, action_state.get_selected_entry(prompt_bufnr).value)
            end)
            return true
          end,
        })
        :find()
    end

    select()
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
  local list = {}

  -- Get all of the valid buffers to display to the user
  local buffers = vim.api.nvim_list_bufs()
  for _, bufnr in ipairs(buffers) do
    if vim.fn.buflisted(bufnr) == 1 then
      local ft = vim.api.nvim_buf_get_option(bufnr, "filetype")
      local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")

      if api.nvim_buf_is_valid(bufnr) and api.nvim_buf_is_loaded(bufnr) and buftype == "" and ft ~= "codecompanion" then
        table.insert(list, buf_utils.get_info(bufnr))
      end
    end
  end

  -- Reorder the list so the buffer that the user initiated the chat from is at the top
  for i, buf in ipairs(list) do
    if buf.bufnr == self.Chat.context.bufnr then
      table.remove(list, i)
      table.insert(list, 1, buf)
      break
    end
  end

  if self.config.opts and self.config.opts.provider then
    local provider = Providers[self.config.opts.provider]
    if not provider then
      return log:error("Provider for slash commands not found: %s", self.config.opts.provider)
    end
    provider(self, list)
  else
    Providers.default(self, list)
  end
end

return SlashCommandBuffer
