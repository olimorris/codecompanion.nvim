local config = require("codecompanion.config")
local file_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.Chat.Memory.Parser
---@field content string The content of the memory file
---@field meta? { included_files: string[] } The filename of the memory file

local M = {}

---Resolve the parser from the config
---@param parser string
---@return CodeCompanion.Chat.Memory.Parser|nil
function M.resolve(parser)
  if not parser then
    return nil
  end

  local ok, err, resolved

  assert(type(parser) == "string", "Parser must be a string")
  assert(
    config and config.memory and config.memory.parsers and config.memory.parsers[parser],
    "Couldn't find the " .. parser .. " parser in the config"
  )

  parser = config.memory.parsers[parser]

  -- If the config entry is a function that returns a parser table, call it.
  if type(parser) == "function" then
    ok, resolved = pcall(parser)
    if not ok then
      log:error("[Memory] Parser factory error: %s", resolved)
      return nil
    end
    return resolved
  end

  if type(parser) == "string" then
    -- The parser might be a CodeCompanion default one ...
    ok, resolved = pcall(require, "codecompanion.strategies.chat.memory.parsers." .. parser)
    if ok then
      return resolved
    end

    -- Or one that exists on the user's disk
    parser = vim.fs.normalize(parser)
    if not file_utils.exists(parser) then
      return log:error("[Memory] Could not find the file %s", parser)
    end

    ok, resolved = pcall(require, parser)
    if ok then
      return resolved
    end

    resolved, err = loadfile(parser)
    if err then
      return log:error("[Memory] %s", err)
    end

    if resolved then
      return resolved()
    end
  end

  return nil
end

---Parse the content through the parser and return it
---@param file CodeCompanion.Chat.Memory.ProcessedFile The processed file
---@param group_parser? string The parser from the group level
---@return CodeCompanion.Chat.Memory.Parser The parsed content, or a parser object
function M.parse(file, group_parser)
  local parser

  -- If the parser exists at a file level, that takes precedence
  if file.parser then
    parser = M.resolve(file.parser)
    if parser then
      local ok, parsed = pcall(parser, file)
      if not ok then
        log:error("[Memory] Parser error: %s", parsed)
        return { content = file.content }
      end

      assert(parsed.content, "Parser must return content")
      return parsed
    end
  end

  -- Otherwise, we take the parser at the group level
  if group_parser then
    parser = M.resolve(group_parser)
    if parser then
      local ok, parsed = pcall(parser, file)
      if not ok then
        log:error("[Memory] Parser error: %s", parsed)
        return { content = file.content }
      end

      assert(parsed.content, "Parser must return content")
      return parsed
    end
  end

  -- Or return unchanged content
  return { content = file.content }
end

return M
