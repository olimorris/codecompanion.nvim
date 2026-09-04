local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

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

  assert(type(parser) == "string", "Parser must be a string")
  assert(
    config and config.rules and config.rules.parsers and config.rules.parsers[parser],
    "Couldn't find the " .. parser .. " parser in the config"
  )

  local value = config.rules.parsers[parser]
  local resolved = utils.resolve({ value = value, source = "Rules" })

  -- A parser module is itself a function, so only a function in the config is a factory
  if type(value) == "function" then
    local ok, output = pcall(resolved)
    if not ok then
      return log:error("[Rules] Parser factory error: %s", output)
    end
    return output
  end

  return resolved
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
