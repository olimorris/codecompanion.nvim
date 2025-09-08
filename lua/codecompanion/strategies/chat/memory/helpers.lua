local config = require("codecompanion.config")

local M = {}

---List all of the memory from the config
---@return table
function M.list()
  local memory_items = {}
  local exclusions = { "opts", "parsers" }

  for name, data in pairs(config.memory) do
    if not vim.tbl_contains(exclusions, name) then
      table.insert(memory_items, {
        name = name,
        description = data.description,
        opts = data.opts,
        parser = data.parser,
        rules = data.rules,
      })
    end
  end

  return memory_items
end

---Add context to the chat based on the memory rules
---@param rules CodeCompanion.Chat.Memory.ProcessedRule
---@param chat CodeCompanion.Chat
---@return nil
function M.add_context(rules, chat)
  for _, item in ipairs(rules) do
    local id = "<memory>" .. item.name .. "</memory>"
    chat:add_context({
      content = item.content,
    }, item.name, id, { tag = "memory" })
  end
end

return M
