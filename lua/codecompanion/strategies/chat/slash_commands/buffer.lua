local config = require("codecompanion.config")

local buf = require("codecompanion.utils.buffers")
local file_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils.util")

local api = vim.api
local fmt = string.format

CONSTANTS = {
  NAME = "Buffer",
  PROMPT = "Select a buffer",
  PROMPT_MULTI = "Select buffers",
  DISPLAY = "name",
}

---Output from the slash command in the chat buffer
---@param SlashCommand CodeCompanion.SlashCommand
---@param selected table The selected item from the provider { name = string, bufnr = number, path = string }
---@return nil
local function output(SlashCommand, selected)
  if not config.opts.send_code and (SlashCommand.config.opts and SlashCommand.config.opts.contains_code) then
    return log:warn("Sending of code has been disabled")
  end

  local filename = vim.fn.fnamemodify(selected.path, ":t")

  -- If the buffer is not loaded, then read the file
  local content
  if not api.nvim_buf_is_loaded(selected.bufnr) then
    content = file_utils.read(selected.path)
    if content == "" then
      return log:warn("Could not read the file: %s", selected.path)
    end
    content = "```" .. file_utils.get_filetype(selected.path) .. "\n" .. content .. "\n```"
  else
    content = buf.format(selected.bufnr)
  end

  local id = SlashCommand.Chat.References:make_id_from_buf(selected.bufnr)

  SlashCommand.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = fmt(
      [[Here is the content from `%s` (which has a buffer number of _%d_ and a filepath of `%s`):

%s]],
      filename,
      selected.bufnr,
      selected.path,
      content
    ),
  }, { reference = id, visible = false })

  SlashCommand.Chat.References:add({
    source = "slash_command",
    name = "buffer",
    id = id,
  })

  util.notify(fmt("Buffer `%s` content added to the chat", filename))
end

local Providers = {
  ---The default provider
  ---@param SlashCommand CodeCompanion.SlashCommand
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
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  telescope = function(SlashCommand)
    local ok, telescope = pcall(require, "telescope.builtin")
    if not ok then
      return log:error("Telescope is not installed")
    end

    telescope.buffers({
      prompt_title = CONSTANTS.PROMPT_MULTI,
      ignore_current_buffer = true, -- Ignore the codecompanion buffer when selecting buffers
      attach_mappings = function(prompt_bufnr, _)
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")

        actions.select_default:replace(function()
          local picker = action_state.get_current_picker(prompt_bufnr)
          local selections = picker:get_multi_selection()

          if vim.tbl_isempty(selections) then
            selections = { action_state.get_selected_entry() }
          end

          actions.close(prompt_bufnr)
          vim.iter(selections):each(function(selection)
            if selection then
              output(SlashCommand, {
                bufnr = selection.bufnr,
                name = selection.filename,
                path = selection.path,
              })
            end
          end)
        end)

        return true
      end,
    })
  end,

  mini_pick = function(SlashCommand)
    local ok, mini_pick = pcall(require, "mini.pick")
    if not ok then
      return log:error("mini.pick is not installed")
    end

    mini_pick.builtin.buffers({ include_current = false }, {
      source = {
        name = CONSTANTS.PROMPT,
        choose = function(selection)
          local success, _ = pcall(function()
            output(SlashCommand, {
              bufnr = selection.bufnr,
              name = selection.text,
              path = selection.text,
            })
          end)
          if success then
            return nil
          end
        end,
        choose_marked = function(selection)
          for _, selected in ipairs(selection) do
            local success, _ = pcall(function()
              output(SlashCommand, {
                bufnr = selected.bufnr,
                name = selected.text,
                path = selected.text,
              })
            end)
            if not success then
              break
            end
          end
        end,
      },
    })
  end,

  ---The fzf-lua provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  fzf_lua = function(SlashCommand)
    local ok, fzf_lua = pcall(require, "fzf-lua")
    if not ok then
      return log:error("fzf-lua is not installed")
    end

    fzf_lua.buffers({
      prompt = CONSTANTS.PROMPT,
      actions = {
        ["default"] = function(selected, o)
          if selected then
            local file = fzf_lua.path.entry_to_file(selected[1], o)
            output(SlashCommand, {
              bufnr = file.bufnr,
              name = file.path,
              path = file.bufname,
            })
          end
        end,
      },
    })
  end,
}

---@class CodeCompanion.SlashCommand.Buffer: CodeCompanion.SlashCommand
local SlashCommand = {}

---@param args CodeCompanion.SlashCommandArgs
function SlashCommand.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommand })

  return self
end

---Execute the slash command
---@return nil
function SlashCommand:execute()
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
    local provider = Providers[self.config.opts.provider] --[[@type function]]
    if not provider then
      return log:error("Provider for the buffer slash command could not be found: %s", self.config.opts.provider)
    end
    return provider(self)
  end
end

return SlashCommand
