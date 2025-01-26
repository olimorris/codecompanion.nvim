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
local util = require("codecompanion.utils")

local fmt = string.format
local get_node_text = vim.treesitter.get_node_text --[[@type function]]

CONSTANTS = {
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

  ---The Telescope provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  telescope = function(SlashCommand)
    local telescope = require("codecompanion.providers.slash_commands.telescope")
    telescope = telescope.new({
      title = CONSTANTS.PROMPT,
      output = function(selection)
        return SlashCommand:output({ relative_path = selection[1], path = selection.path })
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
  -- weird TypeScript bug for vim.filetype.match
  -- see: https://github.com/neovim/neovim/issues/27265
  if not ft then
    local base_name = vim.fs.basename(selected.path)
    local split_name = vim.split(base_name, "%.")
    if #split_name > 1 then
      local ext = split_name[#split_name]
      if ext == "ts" then
        ft = "typescript"
      end
    end
  end
  local content = path.new(selected.path):read()

  local query = vim.treesitter.query.get(ft, "symbols")

  if not query then
    return no_query(ft)
  end

  local parser = vim.treesitter.get_string_parser(content, ft)
  local tree = parser:parse()[1]

  local symbols = {}
  for _, matches, metadata in query:iter_matches(tree:root(), content) do
    local match = vim.tbl_extend("force", {}, metadata)
    for id, nodes in pairs(matches) do
      local node = type(nodes) == "table" and nodes[1] or nodes
      match = vim.tbl_extend("keep", match, {
        [query.captures[id]] = {
          metadata = metadata[id],
          node = node,
        },
      })
    end

    local name_match = match.name or {}
    local symbol_node = (match.symbol or match.type or {}).node

    if not symbol_node then
      goto continue
    end

    local start_node = (match.start or {}).node or symbol_node
    local end_node = (match["end"] or {}).node or start_node

    local kind = match.kind

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

    vim
      .iter(kinds)
      :filter(function(k)
        return kind == k
      end)
      :each(function(k)
        local range = range_from_nodes(start_node, end_node)
        if name_match.node then
          local name = vim.trim(get_node_text(name_match.node, content)) or "<parse error>"

          table.insert(symbols, fmt("- %s: `%s` (from line %s to %s)", k:lower(), name, range.lnum, range.end_lnum))
        end
      end)

    ::continue::
  end

  if #symbols == 0 then
    return no_symbols()
  end

  local id = "<symbols>" .. (selected.relative_path or selected.path) .. "</symbols>"
  content = table.concat(symbols, "\n")

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
