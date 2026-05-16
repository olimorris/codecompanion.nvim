--[[
===============================================================================
    File:       codecompanion.interactions.shared.rules/parsers/cli.lua
    Author:     Oli Morris
-------------------------------------------------------------------------------
    Description:
      Parses a markdown file and extracts any lines that start with "@" as
      file paths. Unlike the claude parser, this returns no content — only
      file references. Designed for CLI interactions where the agent reads
      files directly.
===============================================================================
--]]

---@param file CodeCompanion.Chat.Rules.ProcessedFile
---@return CodeCompanion.Chat.Rules.Parser
return function(file)
  local content = file.content or ""
  local included_files = {}

  if content == "" then
    return { content = "" }
  end

  local ok, parser = pcall(vim.treesitter.get_string_parser, content, "markdown")
  if not ok then
    return { content = "" }
  end

  local tree = parser:parse()[1]
  if not tree then
    return { content = "" }
  end
  local root = tree:root()

  local query = vim.treesitter.query.parse("markdown", "(paragraph) @p")
  local get_text = vim.treesitter.get_node_text

  -- Resolve relative @includes against the directory of the source file
  local source_dir = file.path and vim.fn.fnamemodify(file.path, ":h") or nil

  local seen = {}
  for id, node in query:iter_captures(root, content, 0, -1) do
    if query.captures[id] == "p" then
      local para = get_text(node, content)
      for line in para:gmatch("[^\n]+") do
        local path = line:match("^%s*@(%S+)")
        if path and not seen[path] then
          seen[path] = true
          -- If path is relative and source file is outside cwd, resolve against source dir
          if source_dir and not path:match("^[/~]") then
            local resolved = vim.fs.normalize(vim.fs.joinpath(source_dir, path))
            if vim.fn.filereadable(resolved) == 1 then
              path = resolved
            end
          end
          table.insert(included_files, path)
        end
      end
    end
  end

  return { content = "", meta = (#included_files > 0) and { included_files = included_files } or nil }
end
