local config = require("codecompanion.config")
local file_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.Chat.Rules.Parser
---@field content string The content of the rules file
---@field meta? { included_files: string[] } The filename of the rules file

local M = {}

---Resolve the parser from the config
---@param parser string
---@return CodeCompanion.Chat.Rules.Parser|nil
function M.resolve(parser)
  if not parser then
    return nil
  end

  local ok, err, resolved

  assert(type(parser) == "string", "Parser must be a string")
  assert(
    config and config.rules and config.rules.parsers and config.rules.parsers[parser],
    "Couldn't find the " .. parser .. " parser in the config"
  )

  parser = config.rules.parsers[parser]

  -- If the config entry is a function that returns a parser table, call it.
  if type(parser) == "function" then
    ok, resolved = pcall(parser)
    if not ok then
      log:error("[Rules] Parser factory error: %s", resolved)
      return nil
    end
    return resolved
  end

  if type(parser) == "string" then
    -- The parser might be a CodeCompanion default one ...
    ok, resolved = pcall(require, "codecompanion.strategies.chat.rules.parsers." .. parser)
    if ok then
      return resolved
    end

    -- Or one that exists on the user's disk
    parser = vim.fs.normalize(parser)
    if not file_utils.exists(parser) then
      return log:error("[Rules] Could not find the file %s", parser)
    end

    ok, resolved = pcall(require, parser)
    if ok then
      return resolved
    end

    resolved, err = loadfile(parser)
    if err then
      return log:error("[Rules] %s", err)
    end

    if resolved then
      return resolved()
    end
  end

  return nil
end

---Parse the content through the parser and return it
---@param file CodeCompanion.Chat.Rules.ProcessedFile The processed file
---@param group_parser? string The parser from the group level
---@return CodeCompanion.Chat.Rules.Parser The parsed content, or a parser object
function M.parse(file, group_parser)
  local parser

  -- If the parser exists at a file level, that takes precedence
  if file.parser then
    parser = M.resolve(file.parser)
    if parser then
      local ok, parsed = pcall(parser, file)
      if not ok then
        log:error("[Rules] Parser error: %s", parsed)
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
        log:error("[Rules] Parser error: %s", parsed)
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
