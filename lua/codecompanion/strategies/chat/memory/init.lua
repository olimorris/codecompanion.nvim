local Path = require("plenary.path")
local Scandir = require("plenary.scandir")

local helpers = require("codecompanion.strategies.chat.memory.helpers")
local parsers = require("codecompanion.strategies.chat.memory.parsers")

---@class CodeCompanion.Chat.Memory.ProcessedRule
---@field name string The name of the memory rule
---@field content string The content of the memory rule
---@field filename string The filename of the memory rule
---@field parser string|nil The parser to use for the memory rule
---@field path string The full, normalized file path of the memory rule

---@class CodeCompanion.Chat.Memory
---@field name string The name of the memory group
---@field opts table Additional options for the memory instance
---@field parser string|table|function|nil The parser to use for the memory group
---@field processed CodeCompanion.Chat.Memory.ProcessedRule[] The processed rules
---@field rules string[]|{ path: string, parser: string} The memory rules as an array of strings
local Memory = {}

---@class CodeCompanion.Chat.MemoryArgs
---@field name string The name of the memory instance
---@field opts table Additional options for the memory instance
---@field rules table The memory rules as an array of strings
function Memory.init(args)
  local self = setmetatable({
    name = args.name,
    opts = args.opts,
    parser = args.parser,
    rules = args.rules,

    -- Internal use
    processed = {},
  }, { __index = Memory })
  ---@cast self CodeCompanion.Chat.Memory

  return self
end

---Extract the memory from the rules file
---@return CodeCompanion.Chat.Memory
function Memory:extract()
  local function add_file(fullpath, rule_parser)
    local normalized_file = vim.fs.normalize(fullpath)
    local p = Path:new(normalized_file)
    if p:exists() and not p:is_dir() then
      local ok, content = pcall(function()
        return p:read()
      end)
      if ok then
        table.insert(self.processed, {
          name = normalized_file,
          content = content,
          path = normalized_file,
          filename = vim.fn.fnamemodify(normalized_file, ":t"),
          parser = rule_parser,
        })
      end
    end
  end

  local function walk_dir(dir, rule_parser)
    local entries = Scandir.scan_dir(dir, {
      add_dirs = false,
      hidden = true,
      respect_gitignore = false,
      depth = math.huge,
    })
    for _, entry in ipairs(entries) do
      add_file(entry, rule_parser)
    end
  end

  for _, rule in ipairs(self.rules) do
    local path = rule
    local rule_parser = nil

    if type(rule) == "table" then
      assert(rule.path, "Rule table must contain a 'path' key")
      path = rule.path
      rule_parser = rule.parser
    end

    -- Expand glob patterns (e.g. "dir/**", "src/*.md")
    if tostring(path):match("[%*%?%[]") then
      local matches = vim.fn.glob(path, false, true) or {}
      for _, m in ipairs(matches) do
        local p = vim.fs.normalize(m)
        local filepath = Path:new(p)
        if filepath:exists() then
          if filepath:is_dir() then
            walk_dir(p, rule_parser)
          else
            add_file(p, rule_parser)
          end
        end
      end
      goto continue
    end

    local normalized = vim.fs.normalize(path)
    local filepath = Path:new(normalized)

    if filepath:exists() then
      if filepath:is_dir() then
        walk_dir(normalized, rule_parser)
      else
        add_file(normalized, rule_parser)
      end
    end
    ::continue::
  end

  return self
end

---Parse the memory contents
---@return CodeCompanion.Chat.Memory
function Memory:parse()
  vim.iter(self.processed):each(function(rule)
    rule.content = parsers.parse(rule, self.parser)
  end)

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
