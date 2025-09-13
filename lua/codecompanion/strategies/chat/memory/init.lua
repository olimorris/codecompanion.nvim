local Path = require("plenary.path")
local Scandir = require("plenary.scandir")

local config = require("codecompanion.config")
local helpers = require("codecompanion.strategies.chat.memory.helpers")
local parsers = require("codecompanion.strategies.chat.memory.parsers")

---@class CodeCompanion.Chat.Memory.ProcessedFile
---@field name string The name of the memory file
---@field content string The content of the memory file
---@field filename string The filename of the memory file
---@field meta? {included_files: string[]} Additional metadata about the memory file
---@field parser string|nil The parser to use for the memory file
---@field path string The full, normalized file path of the memory file

---@class CodeCompanion.Chat.Memory
---@field name string The name of the memory group
---@field opts table Additional options for the memory instance
---@field parser string|table|function|nil The parser to use for the memory group
---@field processed CodeCompanion.Chat.Memory.ProcessedFile[] The processed files
---@field files string[]|{ path: string, parser: string} The memory files as an array of strings
local Memory = {}

---@class CodeCompanion.Chat.MemoryArgs
---@field name string The name of the memory instance
---@field opts table Additional options for the memory instance
---@field parser string|function|nil The parser to use for the memory group
---@field files table The memory files as an array of strings
function Memory.init(args)
  local self = setmetatable({
    name = args.name,
    opts = args.opts,
    parser = args.parser,
    files = args.files,

    -- Internal use
    processed = {},
  }, { __index = Memory })
  ---@cast self CodeCompanion.Chat.Memory

  return self
end

---Extract the memory from the files file
---@return CodeCompanion.Chat.Memory
function Memory:extract()
  local function add_file(fullpath, file_parser)
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
          parser = file_parser,
        })
      end
    end
  end

  local function walk_dir(dir, file_parser)
    local entries = Scandir.scan_dir(dir, {
      add_dirs = false,
      hidden = true,
      respect_gitignore = false,
      depth = math.huge,
    })
    for _, entry in ipairs(entries) do
      add_file(entry, file_parser)
    end
  end

  for _, file in ipairs(self.files) do
    local path = file
    local file_parser = nil

    if type(file) == "table" then
      assert(file.path, "file table must contain a 'path' key")
      path = file.path
      file_parser = file.parser
    end

    -- Expand glob patterns (e.g. "dir/**", "src/*.md")
    if tostring(path):match("[%*%?%[]") then
      local matches = vim.fn.glob(path, false, true) or {}
      for _, m in ipairs(matches) do
        local p = vim.fs.normalize(m)
        local filepath = Path:new(p)
        if filepath:exists() then
          if filepath:is_dir() then
            walk_dir(p, file_parser)
          else
            add_file(p, file_parser)
          end
        end
      end
      goto continue
    end

    local normalized = vim.fs.normalize(path)
    local filepath = Path:new(normalized)

    if filepath:exists() then
      if filepath:is_dir() then
        walk_dir(normalized, file_parser)
      else
        add_file(normalized, file_parser)
      end
    end
    ::continue::
  end

  return self
end

---Parse the memory contents
---@return CodeCompanion.Chat.Memory
function Memory:parse()
  vim.iter(self.processed):each(function(file)
    local parsed = parsers.parse(file, self.parser)
    if parsed then
      file.content = parsed.content
      file.meta = parsed.meta
    end
  end)

  return self
end

---Memory should be added as context
---@param chat CodeCompanion.Chat
function Memory:add(chat)
  local included_files = {}
  for _, file in ipairs(self.processed) do
    if file.meta and file.meta.included_files then
      for _, f in ipairs(file.meta.included_files) do
        table.insert(included_files, f)
      end
    end
  end

  helpers.add_context(self.processed, chat)
  if #included_files > 0 then
    helpers.add_files_or_buffers(included_files, chat)
  end
end

---Make the memory message
---@param chat CodeCompanion.Chat
---@return nil
function Memory:make(chat)
  local condition = config
    and config.memory
    and config.memory.opts
    and config.memory.opts.chat
    and config.memory.opts.chat.condition

  if condition ~= nil then
    local ctype = type(condition)

    if ctype == "function" then
      local ok, result = pcall(condition, chat)
      if not ok or not result then
        return
      end
    elseif ctype == "boolean" then
      if not condition then
        return
      end
    end
  end

  return self:extract():parse():add(chat)
end

---Add memory to the chat based on the provided options (external API)
---@param opts CodeCompanion.Chat.MemoryArgs The memory options
---@param chat CodeCompanion.Chat The chat instance
---@return nil
function Memory.add_to_chat(opts, chat)
  local memory = Memory.init(opts)
  return memory:make(chat)
end

return Memory
