local config = require("codecompanion.config")
local providers = require("codecompanion.helpers.slash_commands.shared.files")

local file_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils.util")

local fmt = string.format

---@class CodeCompanion.SlashCommand.Symbols: CodeCompanion.SlashCommand
---@field new fun(args: CodeCompanion.SlashCommand): CodeCompanion.SlashCommand.Symbols
---@field execute fun(self: CodeCompanion.SlashCommand.Symbols)
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
  if not config.opts.send_code and (self.config.opts and self.config.opts.contains_code) then
    return log:warn("Sending of code has been disabled")
  end

  local function output(SlashCommand, selected)
    local ft = file_utils.get_filetype(selected.path)
    local content = file_utils.read(selected.path)

    local Chat = self.Chat
    local bufnr = self.Chat.context.bufnr

    local query = vim.treesitter.query.get(ft, "symbols")

    local parser = vim.treesitter.get_string_parser(content, ft)
    local tree = parser:parse()[1]

    local function get_ts_node(output_tbl, type, match)
      table.insert(
        output_tbl,
        fmt(" - %s %s", type, vim.trim(vim.treesitter.get_node_text(match.node, content, match)))
      )
    end

    local symbols = {}
    for _, matches, metadata in query:iter_matches(tree:root(), bufnr, 0, -1, { all = false }) do
      local match = vim.tbl_extend("force", {}, metadata)
      for id, node in pairs(matches) do
        match = vim.tbl_extend("keep", match, {
          [query.captures[id]] = {
            metadata = metadata[id],
            node = node,
          },
        })
      end

      local symbol_node = (match.symbol or {}).node

      if not symbol_node then
        goto continue
      end

      local name_match = match.name or {}
      local kind = match.kind

      local kinds = {
        "Module",
        "Class",
        "Method",
        "Function",
      }

      vim
        .iter(kinds)
        :filter(function(k)
          return kind == k
        end)
        :each(function(k)
          get_ts_node(symbols, k:lower(), name_match)
        end)

      ::continue::
    end

    if #symbols == 0 then
      log:info("No symbols found in the buffer")
      util.notify("No symbols found in the buffer")
      return
    end

    local content = table.concat(symbols, "\n")
    Chat:add_message({
      role = config.constants.USER_ROLE,
      content = fmt(
        [[Here is a symbolic outline of the file `%s` with filetype `%s`:

<symbols>
%s
</symbols>]],
        Chat.context.filename,
        Chat.context.filetype,
        content
      ),
    }, { visible = false })
    util.notify("Symbolic outline added to chat")
  end

  if self.config.opts and self.config.opts.provider then
    local provider = providers[self.config.opts.provider] --[[@type function]]
    if not provider then
      return log:error("Provider for the file slash command could not found: %s", self.config.opts.provider)
    end
    provider(self, output)
  else
    providers.default(self, output)
  end
end

return SlashCommand
