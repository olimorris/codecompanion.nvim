local file_utils = require("codecompanion.utils.files")
local helpers = require("codecompanion.strategies.chat.memory.helpers")

---@class CodeCompanion.Chat.Memory.ProcessedRule
---@field content string The content of the memory rule
---@field filename string The filename of the memory rule
---@field filepath string The full file path of the memory rule
---@field parser string|nil The parser to use for the memory rule

---@class CodeCompanion.Chat.Memory
---@field name string The name of the memory instance
---@field rules string[]|{ path: string, parser: string} The memory rules as an array of strings
---@field opts table Additional options for the memory instance
---@field processed CodeCompanion.Chat.Memory.ProcessedRule[] The processed rules
local Memory = {}

---@class CodeCompanion.Chat.MemoryArgs
---@field name string The name of the memory instance
---@field rules table The memory rules as an array of strings
---@field opts table Additional options for the memory instance
function Memory.init(args)
  local self = setmetatable({
    name = args.name,
    rules = args.rules,
    opts = args.opts,
    -- Internal use
    processed = {},
  }, { __index = Memory })
  ---@cast self CodeCompanion.Chat.Memory

  return self
end

---Extract the memory from the rules file
---@return CodeCompanion.Chat.Memory
function Memory:extract()
  for _, rule in ipairs(self.rules) do
    local path = rule
    if type(rule) == "table" then
      assert(rule.path, "Rule table must contain a 'path' key")
      path = rule.path
    end

    local normalized = vim.fs.normalize(path)

    if file_utils.exists(normalized) then
      local ok, content = pcall(file_utils.read, normalized)
      if ok then
        table.insert(self.processed, {
          name = path,
          content = content,
          filepath = normalized,
          filename = vim.fn.fnamemodify(path, ":t"),
          parser = rule.parser,
        })
      end
    end
  end

  return self
end

---Parse the memory contents
---@return CodeCompanion.Chat.Memory
function Memory:parse()
  return self
end

---Memory should be added as context
---@param chat CodeCompanion.Chat
function Memory:add(chat)
  helpers.add_context(self.processed, chat)
end

---Make the memory message
---@param chat CodeCompanion.Chat
---@return nil
function Memory:make(chat)
  return self:extract():parse():add(chat)
end

return Memory
