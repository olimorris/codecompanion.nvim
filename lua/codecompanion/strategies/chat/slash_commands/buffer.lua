local config = require("codecompanion.config")

local buf = require("codecompanion.utils.buffers")
local file_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils.util")

local api = vim.api
local fmt = string.format

CONSTANTS = {
  NAME = "Buffer",
  PROMPT = "Select buffer(s)",
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

  util.notify(fmt("Added buffer `%s` to the chat", filename))
end

local providers = {
  ---The default provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  default = function(SlashCommand)
    local default = require("codecompanion.providers.slash_commands.default")
    default = default
      .new({
        output = function(selection)
          output(SlashCommand, selection)
        end,
        SlashCommand = SlashCommand,
        title = CONSTANTS.PROMPT,
      })
      :buffers()
      :display()
  end,

  ---The Telescope provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  telescope = function(SlashCommand)
    local telescope = require("codecompanion.providers.slash_commands.telescope")
    telescope = telescope.new({
      title = CONSTANTS.PROMPT,
      output = function(selection)
        return output(SlashCommand, {
          bufnr = selection.bufnr,
          name = selection.filename,
          path = selection.path,
        })
      end,
    })

    telescope.provider.buffers({
      prompt_title = telescope.title,
      ignore_current_buffer = true, -- Ignore the codecompanion buffer when selecting buffers
      attach_mappings = telescope:display(),
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
        return output(SlashCommand, selected)
      end,
    })

    mini_pick.provider.builtin.buffers(
      { include_current = false },
      mini_pick:display(function(selected)
        return {
          bufnr = selected.bufnr,
          name = selected.text,
          path = selected.text,
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
        return output(SlashCommand, selected)
      end,
    })

    fzf.provider.buffers(fzf:display(function(selected, opts)
      local file = fzf.provider.path.entry_to_file(selected, opts)
      return {
        bufnr = file.bufnr,
        name = file.path,
        path = file.bufname,
      }
    end))
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
---@param SlashCommands CodeCompanion.SlashCommands
---@return nil
function SlashCommand:execute(SlashCommands)
  if not config.opts.send_code and (self.config.opts and self.config.opts.contains_code) then
    return log:warn("Sending of code has been disabled")
  end
  return SlashCommands:set_provider(self, providers)
end

return SlashCommand
