local file_utils = require("codecompanion.utils.files")

---@class CodeCompanion.Chat.Memory.ProcessedRule
---@field content string The content of the memory rule
---@field filename string The filename of the memory rule
---@field path string The path to the memory rule
---@field role string The role for message

---@class CodeCompanion.Chat.Memory
---@field name string The name of the memory instance
---@field rules table The memory rules as an array of strings
---@field role string The role for message
---@field opts table Additional options for the memory instance
---@field processed CodeCompanion.Chat.Memory.ProcessedRule[] The processed rules
local Memory = {}

---@class CodeCompanion.Chat.MemoryArgs
---@field name string The name of the memory instance
---@field rules table The memory rules as an array of strings
---@field role string The role for message
---@field opts table Additional options for the memory instance
function Memory.init(args)
  local self = setmetatable({
    name = args.name,
    rules = args.rules,
    role = args.role or "system",
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

---Format the memory as a chat message
---@return CodeCompanion.Chat.Messages
function Memory:add()
  local messages = {}
  for _, item in ipairs(self.processed) do
    table.insert(messages, {
      role = self.role,
      content = item.content,
      opts = {
        visible = false,
        tag = "memory_" .. self.name,
      },
    })
  end
  return messages
end

---Make the memory message
---@return nil
function Memory:make()
  return self:extract():parse():add()
end

return Memory
