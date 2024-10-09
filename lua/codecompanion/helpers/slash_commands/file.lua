local config = require("codecompanion.config")

local file_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils.util")

CONSTANTS = {
  NAME = "File",
  PROMPT = "Select a file",
}

---Output from the slash command in the chat buffer
---@param SlashCommand CodeCompanion.SlashCommand
---@param selected table The selected item from the provider { relative_path = string, path = string }
---@return nil
local function output(SlashCommand, selected)
  if not config.opts.send_code and (SlashCommand.config.opts and SlashCommand.config.opts.contains_code) then
    return log:warn("Sending of code has been disabled")
  end

  local ft = file_utils.get_filetype(selected.path)
  local content = file_utils.read(selected.path)

  if content == "" then
    return log:warn("Could not read the file: %s", selected.path)
  end

  local Chat = SlashCommand.Chat
  local relative_path = selected.relative_path or selected[1] or selected.path
  Chat:add_message({
    role = "user",
    content = string.format(
      [[Here is the content from the file `%s`:

```%s
%s
```]],
      relative_path,
      ft,
      content
    ),
  }, { visible = false })
  util.notify("File data added to chat")
end

local Providers = {
  ---The Telescope provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  telescope = function(SlashCommand)
    local ok, telescope = pcall(require, "telescope.builtin")
    if not ok then
      return log:error("Telescope is not installed")
    end

    telescope.find_files({
      prompt_title = CONSTANTS.PROMPT,
      attach_mappings = function(prompt_bufnr, map)
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")

        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            selection = { relative_path = selection[1], path = selection.path }
            output(SlashCommand, selection)
          end
        end)

        return true
      end,
    })
  end,

  ---The mini.pick provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  mini_pick = function(SlashCommand)
    local ok, mini_pick = pcall(require, "mini.pick")
    if not ok then
      return log:error("mini.pick is not installed")
    end
    mini_pick.builtin.files({}, {
      source = {
        name = CONSTANTS.PROMPT,
        choose = function(path)
          local success, _ = pcall(function()
            output(SlashCommand, { path = path })
          end)
          if success then
            return nil
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

    fzf_lua.files({
      prompt = CONSTANTS.PROMPT,
      actions = {
        ["default"] = function(selected, o)
          if not selected or #selected == 0 then
            return
          end
          local file = fzf_lua.path.entry_to_file(selected[1], o)
          local selection = { relative_path = file.stripped, path = file.path }
          output(SlashCommand, selection)
        end,
      },
    })
  end,
}

---@class CodeCompanion.SlashCommand.File: CodeCompanion.SlashCommand
---@field new fun(args: CodeCompanion.SlashCommand): CodeCompanion.SlashCommand.File
---@field execute fun(self: CodeCompanion.SlashCommand.File)
local SlashCommand = {}

---@param args CodeCompanion.SlashCommand
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
  if self.config.opts and self.config.opts.provider then
    local provider = Providers[self.config.opts.provider]
    if not provider then
      return log:error("Provider for the file slash command could not found: %s", self.config.opts.provider)
    end
    provider(self)
  else
    Providers.telescope(self)
  end
end

return SlashCommand
