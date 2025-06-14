local path = require("plenary.path")

local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

local fmt = string.format

local CONSTANTS = {
  NAME = "File",
  PROMPT = "Select file(s)",
}

local providers = {
  ---The default provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  default = function(SlashCommand)
    local default = require("codecompanion.providers.slash_commands.default")
    return default
      .new({
        output = function(selection)
          return SlashCommand:output(selection)
        end,
        SlashCommand = SlashCommand,
        title = CONSTANTS.PROMPT,
      })
      :find_files()
      :display()
  end,

  ---The Snacks.nvim provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  snacks = function(SlashCommand)
    local snacks = require("codecompanion.providers.slash_commands.snacks")
    snacks = snacks.new({
      title = CONSTANTS.PROMPT .. ": ",
      output = function(selection)
        return SlashCommand:output({
          relative_path = selection.file,
          path = vim.fs.joinpath(selection.cwd, selection.file),
        })
      end,
    })

    snacks.provider.picker.pick({
      source = "files",
      prompt = snacks.title,
      confirm = snacks:display(),
      main = { file = false, float = true },
    })
  end,

  ---The Telescope provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  telescope = function(SlashCommand)
    local telescope = require("codecompanion.providers.slash_commands.telescope")
    telescope = telescope.new({
      title = CONSTANTS.PROMPT,
      output = function(selection)
        return SlashCommand:output(selection)
      end,
    })

    telescope.provider.find_files({
      prompt_title = telescope.title,
      attach_mappings = telescope:display(),
      hidden = true,
    })
  end,

  ---The Mini.Pick provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  mini_pick = function(SlashCommand)
    local mini_pick = require("codecompanion.providers.slash_commands.mini_pick")
    mini_pick = mini_pick.new({
      title = CONSTANTS.PROMPT,
      output = function(selected)
        return SlashCommand:output(selected)
      end,
    })

    mini_pick.provider.builtin.files(
      {},
      mini_pick:display(function(selected)
        return {
          path = selected,
        }
      end)
    )
  end,

  ---The fzf-lua provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  fzf_lua = function(SlashCommand)
    local fzf = require("codecompanion.providers.slash_commands.fzf_lua")
    fzf = fzf.new({
      title = CONSTANTS.PROMPT,
      output = function(selected)
        return SlashCommand:output(selected)
      end,
    })

    fzf.provider.files(fzf:display(function(selected, opts)
      local file = fzf.provider.path.entry_to_file(selected, opts)
      return {
        relative_path = file.stripped,
        path = file.path,
      }
    end))
  end,
}

---@class CodeCompanion.SlashCommand.File: CodeCompanion.SlashCommand
local SlashCommand = {}

---@param args CodeCompanion.SlashCommandArgs
function SlashCommand.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
    opts = args.opts,
  }, { __index = SlashCommand })

  return self
end

---Execute the slash command
---@param SlashCommands CodeCompanion.SlashCommands
---@return nil
function SlashCommand:execute(SlashCommands)
  if not config.can_send_code() and (self.config.opts and self.config.opts.contains_code) then
    return log:warn("Sending of code has been disabled")
  end
  return SlashCommands:set_provider(self, providers)
end

---Open and read the contents of the selected file
---@param selected { path: string, relative_path: string?, description: string? }
function SlashCommand:read(selected)
  local ok, content = pcall(function()
    return path.new(selected.path):read()
  end)

  if not ok then
    return ""
  end

  local ft = vim.filetype.match({ filename = selected.path })
  local relative_path = vim.fn.fnamemodify(selected.path, ":.")
  local id = "<file>" .. relative_path .. "</file>"

  return content, ft, id, relative_path
end

---Output from the slash command in the chat buffer
---@param selected { relative_path: string?, path: string, description: string? }
---@param opts? { silent: boolean, pin: boolean }
---@return nil
function SlashCommand:output(selected, opts)
  if not config.can_send_code() and (self.config.opts and self.config.opts.contains_code) then
    return log:warn("Sending of code has been disabled")
  end
  opts = opts or {}

  local content, ft, id, relative_path = self:read(selected)

  if content == "" then
    return log:warn("Could not read the file: %s", selected.path)
  end

  -- Workspaces allow the user to set their own custom description which should take priority
  local description
  if selected.description then
    description = fmt(
      [[%s

```%s
%s
```]],
      selected.description,
      ft,
      content
    )
  else
    description = fmt(
      [[<attachment filepath="%s">%s:

```%s
%s
```
</attachment>]],
      relative_path,
      opts.pin and "Here is the updated content from the file" or "Here is the content from the file",
      ft,
      content
    )
  end

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = description or "",
  }, { reference = id, visible = false })

  if opts.pin then
    return
  end

  self.Chat.references:add({
    id = id or "",
    path = selected.path,
    source = "codecompanion.strategies.chat.slash_commands.file",
  })

  if opts.silent then
    return
  end

  util.notify(fmt("Added the `%s` file to the chat", vim.fn.fnamemodify(relative_path, ":t")))
end

return SlashCommand
