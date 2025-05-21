local path = require("plenary.path")

local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

local ts = vim.treesitter

local line_count = 0

local CONSTANTS = {
  NAME = "Help",
  PROMPT = "Select a help tag",
  MAX_LINES = config.strategies.chat.slash_commands.help.opts.max_lines,
}

---Find the tag row
---@param tag string The tag to find
---@param content string The content of the file
---@return integer The row of the tag
local function get_tag_row(tag, content)
  local ft = "vimdoc"
  local parser = vim.treesitter.get_string_parser(content, "vimdoc")
  local root = parser:parse()[1]:root()
  local query = ts.query.parse(ft, '((tag) @tag (#eq? @tag "*' .. tag .. '*"))')
  for _, node, _ in query:iter_captures(root, content) do
    local tag_row = node:range()
    return tag_row
  end
end

---Trim the content around the tag
---@param content string The content of the file
---@param tag string The tag to find
---@return string The trimmed content
local function trim_content(content, tag)
  local lines = vim.split(content, "\n")
  local tag_row = get_tag_row(tag, content)

  local prefix = ""
  local suffix = ""
  local start_, end_
  if tag_row - CONSTANTS.MAX_LINES / 2 < 1 then
    start_ = 1
    end_ = CONSTANTS.MAX_LINES
    suffix = "\n..."
  elseif tag_row + CONSTANTS.MAX_LINES / 2 > #lines then
    start_ = #lines - CONSTANTS.MAX_LINES
    end_ = #lines
    prefix = "...\n"
  else
    start_ = tag_row - CONSTANTS.MAX_LINES / 2
    end_ = tag_row + CONSTANTS.MAX_LINES / 2
    prefix = "...\n"
    suffix = "\n..."
  end

  content = table.concat(vim.list_slice(lines, start_, end_), "\n")

  return prefix .. content .. suffix
end

---Send the output to the chat buffer
---@param SlashCommand CodeCompanion.SlashCommand
---@param content string The content of the help file
---@param selected table The selected item from the provider { tag = string, path = string }
---@return nil
local function send_output(SlashCommand, content, selected)
  local ft = "vimdoc"
  local Chat = SlashCommand.Chat
  local id = "<help>" .. selected.tag .. "</help>"

  Chat:add_message({
    role = config.constants.USER_ROLE,
    content = string.format(
      [[Help context for `%s`:

```%s
%s
```

Note the path to the help file is `%s`.
]],
      selected.tag,
      ft,
      content,
      selected.path
    ),
  }, { reference = id, visible = false })

  Chat.references:add({
    source = "slash_command",
    name = "help",
    id = id,
  })

  return util.notify(string.format("Added the `%s` help to the chat", selected.tag))
end

---Output from the slash command in the chat buffer
---@param SlashCommand CodeCompanion.SlashCommand
---@param selected table The selected item from the provider { tag = string, path = string }
---@return nil
local function output(SlashCommand, selected)
  if not config.can_send_code() and (SlashCommand.config.opts and SlashCommand.config.opts.contains_code) then
    return log:warn("Sending of code has been disabled")
  end

  local content = path.new(selected.path):read()
  line_count = #vim.split(content, "\n")

  if line_count > CONSTANTS.MAX_LINES then
    vim.ui.select({ "Yes", "No" }, {
      kind = "codecompanion.nvim",
      prompt = "The help file is more than " .. CONSTANTS.MAX_LINES .. " lines. Do you want to trim it?",
    }, function(choice)
      if not choice then
        return
      end
      if choice == "No" then
        return send_output(SlashCommand, content, selected)
      end
      content = trim_content(content, selected.tag)
      return send_output(SlashCommand, content, selected)
    end)
  else
    return send_output(SlashCommand, content, selected)
  end
end

local providers = {
  ---The Snacks.nvim provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  snacks = function(SlashCommand)
    local snacks = require("codecompanion.providers.slash_commands.snacks")
    snacks = snacks.new({
      title = CONSTANTS.PROMPT .. ": ",
      output = function(selection)
        return output(SlashCommand, {
          path = selection.file,
          tag = selection.tag,
        })
      end,
    })

    snacks.provider.picker.pick({
      source = "help",
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
        return output(SlashCommand, {
          path = selection.filename,
          tag = selection.display,
        })
      end,
    })

    telescope.provider.help_tags({
      prompt_title = telescope.title,
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

    mini_pick.provider.builtin.help(
      {},
      mini_pick:display(function(selected)
        return {
          path = selected.filename,
          tag = selected.name,
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

    fzf.provider.helptags(fzf:display(function(selected, opts)
      local file = fzf.provider.path.entry_to_file(selected, opts)
      return {
        path = file.path,
        tag = selected:match("[^%s]+"),
      }
    end))
  end,
}

---@class CodeCompanion.SlashCommand.Help: CodeCompanion.SlashCommand
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

return SlashCommand
