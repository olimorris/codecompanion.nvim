local config = require("codecompanion.config")

local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils.util")

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

  local lang = self.Chat.context.filetype

  local Chat = self.Chat
  local bufnr = self.Chat.context.bufnr
  local query = vim.treesitter.query.get(lang, "symbols")

  local parser = vim.treesitter.get_parser(bufnr, lang)
  local tree = parser:parse()[1]

  local function get_ts_node(output_tbl, type, match)
    table.insert(
      output_tbl,
      string.format(" - %s %s", type, vim.trim(vim.treesitter.get_node_text(match.node, bufnr, match)))
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

    if kind then
      for _, k in ipairs(kinds) do
        if kind == k then
          get_ts_node(symbols, k:lower(), name_match)
        end
      end
    end

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
    content = string.format(
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

return SlashCommand
