--[[
Uses Tree-sitter to parse a given file and extract symbol types and names. Then
displays those symbols in the chat buffer as references. To support tools
and agents, start and end lines for the symbols are also output.

Heavily modified from the awesome Aerial.nvim plugin by stevearc:
https://github.com/stevearc/aerial.nvim/blob/master/lua/aerial/backends/treesitter/init.lua
--]]
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local path = require("plenary.path")
local symbol_utils = require("codecompanion.strategies.chat.helpers")
local util = require("codecompanion.utils")

local fmt = string.format
local get_node_text = vim.treesitter.get_node_text --[[@type function]]

local CONSTANTS = {
  NAME = "Symbols",
  PROMPT = "Select symbol(s)",
}

---Get the range of two nodes
---@param start_node TSNode
---@param end_node TSNode
local function range_from_nodes(start_node, end_node)
  local row, col = start_node:start()
  local end_row, end_col = end_node:end_()
  return {
    lnum = row + 1,
    end_lnum = end_row + 1,
    col = col,
    end_col = end_col,
  }
end

---Return when no symbols query exists
local function no_query(ft)
  util.notify(
    fmt("There are no Tree-sitter symbol queries for `%s` files yet. Please consider making a PR", ft),
    vim.log.levels.WARN
  )
end

---Return when no symbols have been found
local function no_symbols()
  util.notify("No symbols found in the given file", vim.log.levels.WARN)
end

local providers = {
  ---The default provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  default = function(SlashCommand)
    local default = require("codecompanion.providers.slash_commands.default")
    return default
      .new({
        output = function(selection)
          SlashCommand:output({ relative_path = selection.relative_path, path = selection.path })
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
        return SlashCommand:output({
          relative_path = selection[1],
          path = selection.path,
        })
      end,
    })

    telescope.provider.find_files({
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
        return SlashCommand:output(selected)
      end,
    })

    mini_pick.provider.builtin.files(
      {},
      mini_pick:display(function(selected)
        return {
          path = selected,
          relative_path = selected,
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

---@class CodeCompanion.SlashCommand.Symbols: CodeCompanion.SlashCommand
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

  local ft = vim.filetype.match({ filename = selected.path })
  local symbols, content = symbol_utils.extract_file_symbols(selected.path)

  if not symbols then
    return no_query(ft)
  end

  local symbol_descriptions = {}
  local kinds = {
    "Import",
    "Enum",
    "Module",
    "Class",
    "Struct",
    "Interface",
    "Method",
    "Function",
  }

  for _, symbol in ipairs(symbols) do
    if vim.tbl_contains(kinds, symbol.kind) then
      table.insert(
        symbol_descriptions,
        fmt("- %s: `%s` (from line %s to %s)", symbol.kind:lower(), symbol.name, symbol.start_line, symbol.end_line)
      )
    end
  end

  if #symbol_descriptions == 0 then
    return no_symbols()
  end

  local id = "<symbols>" .. (selected.relative_path or selected.path) .. "</symbols>"
  content = table.concat(symbol_descriptions, "\n")

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
      [[Here is a symbolic outline of the file `%s` (with filetype `%s`). I've also included the line numbers that each symbol starts and ends on in the file:

%s

Prompt the user if you need to see more than the symbolic outline.
]],
      selected.relative_path or selected.path,
      ft,
      content
    )
  end

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = description,
  }, { reference = id, visible = false })

  self.Chat.references:add({
    source = "slash_command",
    name = "symbols",
    id = id,
  })

  if opts.silent then
    return
  end

  util.notify(fmt("Added the symbols for `%s` to the chat", vim.fn.fnamemodify(selected.relative_path, ":t")))
end

return SlashCommand
