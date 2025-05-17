local path = require("plenary.path")

local buf = require("codecompanion.utils.buffers")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

local api = vim.api
local fmt = string.format

local CONSTANTS = {
  NAME = "Image",
  PROMPT = "Select an image(s)",
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

-- The different choices the user has to insert an image via a slash command
local choice = {
  ---Share the URL of an image
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  URL = function(SlashCommand)
    return vim.ui.input({ prompt = "Enter the URL: " }, function(input)
      local selected = {
        source = "image_url",
        path = input,
      }
      return SlashCommand:output(selected)
    end)
  end,
}

---@class CodeCompanion.SlashCommand.Image: CodeCompanion.SlashCommand
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
  local choice = vim.ui.select({ "URL", "File" }, {
    prompt = "Select an image source",
  }, function(selected)
    if not selected then
      return
    end
    return choice[selected](self)
  end)
end

---Put a reference to the image in the chat buffer
---@param selected table The selected image { source = string, path = string }
---@param opts? table
---@return nil
function SlashCommand:output(selected, opts)
  local id = "<image>" .. selected.path .. "</image>"

  --TODO: base64 encode this if a file
  local image = selected.path

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = image,
  }, { reference = id, tag = "image", visible = false })

  self.Chat.references:add({
    bufnr = selected.bufnr,
    id = id,
    path = selected.path,
    source = "codecompanion.strategies.chat.slash_commands.image",
  })
end

return SlashCommand
