local buf = require("codecompanion.utils.buffers")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

local fmt = string.format

local CONSTANTS = {
  NAME = "Buffer",
  PROMPT = "Select buffer(s)",
}

local providers = {
  ---The default provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  default = function(SlashCommand)
    local default = require("codecompanion.providers.slash_commands.default")
    default = default
      .new({
        output = function(selection)
          SlashCommand:output(selection)
        end,
        SlashCommand = SlashCommand,
        title = CONSTANTS.PROMPT,
      })
      :buffers()
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
          bufnr = selection.buf,
          name = vim.fn.bufname(selection.buf),
          path = selection.file,
        })
      end,
    })

    snacks.provider.picker.pick({
      source = "buffers",
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
        return SlashCommand:output({
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
        return SlashCommand:output(selected)
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
        return SlashCommand:output(selected)
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
  if not config.can_send_code() and (self.config.opts and self.config.opts.contains_code) then
    return log:warn("Sending of code has been disabled")
  end
  return SlashCommands:set_provider(self, providers)
end

---Output from the slash command in the chat buffer
---@param selected table The selected item from the provider { relative_path = string, path = string }
---@param opts? table
---@return nil
function SlashCommand:output(selected, opts)
  if not config.can_send_code() and (self.config.opts and self.config.opts.contains_code) then
    return log:warn("Sending of code has been disabled")
  end
  opts = opts or {}

  local message = "Here is the content from a file (including line numbers)"
  if opts.pin then
    message = "Here is the updated content from a file (including line numbers)"
  end

  local ok, content, id, filename = pcall(buf.format_for_llm, selected, { message = message })
  if not ok then
    return log:warn(content)
  end

  if opts.description then
    content = opts.description .. "\n\n" .. content
  end

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = content,
  }, { reference = id, visible = false })

  if opts.pin then
    return
  end

  local slash_command_opts = self.config.opts and self.config.opts.default_params or nil
  if slash_command_opts then
    if slash_command_opts == "pin" then
      opts.pinned = true
    elseif slash_command_opts == "watch" then
      opts.watched = true
    end
  end

  self.Chat.references:add({
    bufnr = selected.bufnr,
    id = id,
    path = selected.path,
    opts = opts,
    source = "codecompanion.strategies.chat.slash_commands.buffer",
  })

  if not opts.silent then
    util.notify(fmt("Added buffer `%s` to the chat", filename))
  end
end

return SlashCommand
