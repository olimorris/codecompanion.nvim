--[[
===============================================================================
    File:       codecompanion.interactions/chat/rules/parsers/claude.lua
    Author:     Oli Morris
-------------------------------------------------------------------------------
    Description:
      Parses a CLAUDE.md (or similarly formatted) file, extracting any lines
      that start with "@" as file paths to be included in rules.
===============================================================================
--]]

---@param file CodeCompanion.Chat.Rules.ProcessedFile
---@return CodeCompanion.Chat.Rules.Parser
return function(file)
  local content = file.content or ""
  local included_files = {}

  if content == "" then
    return { content = content }
  end

  -- Parse the markdown content
  local ok, parser = pcall(vim.treesitter.get_string_parser, content, "markdown")
  if not ok then
    return { content = content }
  end

  local tree = parser:parse()[1]
  if not tree then
    return { content = content }
  end
  local root = tree:root()

  -- Single capture query: all paragraph nodes
  local query = vim.treesitter.query.parse("markdown", "(paragraph) @p")
  local get_text = vim.treesitter.get_node_text

  local seen = {}
  for id, node in query:iter_captures(root, content, 0, -1) do
    if query.captures[id] == "p" then
      local para = get_text(node, content)
      for line in para:gmatch("[^\n]+") do
        local path = line:match("^%s*@(%S+)")
        if path and not seen[path] then
          seen[path] = true
          table.insert(included_files, path)
        end
      end
    end
  end

  return { content = content, meta = (#included_files > 0) and { included_files = included_files } or nil }
end
