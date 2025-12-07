local Path = require("plenary.path")
local Scandir = require("plenary.scandir")

local config = require("codecompanion.config")
local helpers = require("codecompanion.interactions.chat.rules.helpers")
local parsers = require("codecompanion.interactions.chat.rules.parsers")

---@class CodeCompanion.Chat.Rules.ProcessedFile
---@field name string The name of the rules file
---@field content string The content of the rules file
---@field filename string The filename of the rules file
---@field meta? {included_files: string[]} Additional metadata about the rules file
---@field parser string|nil The parser to use for the rules file
---@field path string The full, normalized file path of the rules file
---@field system_prompt? string The extracted system prompt from the rules file

---@class CodeCompanion.Chat.Rules
---@field name string The name of the rules group
---@field opts table Additional options for the rules instance
---@field parser string|table|function|nil The parser to use for the rules group
---@field processed CodeCompanion.Chat.Rules.ProcessedFile[] The processed files
---@field files string[]|{ path: string, parser: string} The rules files as an array of strings
local Rules = {}

---@class CodeCompanion.Chat.RulesArgs
---@field name string The name of the rules instance
---@field opts table Additional options for the rules instance
---@field parser string|function|nil The parser to use for the rules group
---@field files table The rules files as an array of strings
function Rules.init(args)
  local self = setmetatable({
    name = args.name,
    opts = args.opts,
    parser = args.parser,
    files = args.files,

    -- Internal use
    processed = {},
  }, { __index = Rules })
  ---@cast self CodeCompanion.Chat.Rules

  return self
end

---Extract the rules from the files file
---@return CodeCompanion.Chat.Rules
function Rules:extract()
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
        local path = Path:new(p)
        if path:exists() then
          if path:is_dir() then
            walk_dir(p, file_parser)
          else
            add_file(p, file_parser)
          end
        end
      end
      goto continue
    end

    local normalized = vim.fs.normalize(path)
    local path = Path:new(normalized)

    if path:exists() then
      if path:is_dir() then
        walk_dir(normalized, file_parser)
      else
        add_file(normalized, file_parser)
      end
    end
    ::continue::
  end

  return self
end

---Parse the rules contents
---@return CodeCompanion.Chat.Rules
function Rules:parse()
  vim.iter(self.processed):each(function(file)
    local parsed = parsers.parse(file, self.parser)
    if parsed then
      file.system_prompt = parsed.system_prompt
      file.content = parsed.content
      file.meta = parsed.meta
    end
  end)

  return self
end

---Rules should be added as context
---@param chat CodeCompanion.Chat
function Rules:add(chat)
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

---Make the rules message
---@param chat CodeCompanion.Chat
---@param opts? { force: boolean } Additional options
---@return nil
function Rules:make(chat, opts)
  opts = vim.tbl_extend("force", { force = false }, opts or {})

  local condition = config
    and config.rules
    and config.rules.opts
    and config.rules.opts.chat
    and config.rules.opts.chat.condition

  if condition ~= nil and opts.force == false then
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

---Add rules to the chat based on the provided options (external API)
---@param opts CodeCompanion.Chat.RulesArgs The rules options
---@param chat CodeCompanion.Chat The chat instance
---@return nil
function Rules.add_to_chat(opts, chat)
  local rules = Rules.init(opts)
  return rules:make(chat)
end

return Rules
