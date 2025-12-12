local file = require("codecompanion.utils.files")
local helpers = require("codecompanion.interactions.chat.rules.helpers")
local log = require("codecompanion.utils.log")
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
---@field files string[]|table[] The rules files as an array of strings or tables
local Rules = {}

---@class CodeCompanion.Chat.RulesArgs
---@field name string The name of the rules instance
---@field opts? table Additional options for the rules instance
---@field parser? string|function|nil The parser to use for the rules group
---@field files table The rules files as an array of strings or tables

---Create a new Rules instance
---@param args CodeCompanion.Chat.RulesArgs
---@return CodeCompanion.Chat.Rules
function Rules.new(args)
  local self = setmetatable({
    name = args.name,
    opts = args.opts or {},
    parser = args.parser,
    files = args.files,

    -- Internal use
    processed = {},
  }, { __index = Rules })
  ---@cast self CodeCompanion.Chat.Rules

  return self
end

---Collect all file paths based on the rules configuration
---@return string[] paths List of absolute file paths
function Rules:collect_files()
  local collected_paths = {}
  local seen = {} -- Track duplicates

  local function add_path(path)
    local normalized = vim.fs.normalize(path)
    if not seen[normalized] then
      seen[normalized] = true
      table.insert(collected_paths, normalized)
    end
  end

  local function add_paths(paths)
    for _, path in ipairs(paths) do
      add_path(path)
    end
  end

  for _, file_spec in ipairs(self.files) do
    local path = file_spec

    -- Handle table format: { path = "...", files = {...}, parser = "..." }
    if type(file_spec) == "table" then
      if not file_spec.path then
        log:warn("[Rules] Invalid file spec format: missing `path` key: %s", vim.inspect(file_spec))
        goto continue
      end

      path = file_spec.path

      -- If files key is present, treat path as a directory and scan for matching files
      if file_spec.files then
        local normalized_dir = vim.fs.normalize(path)

        if not file.exists(normalized_dir) then
          log:warn("[Rules] Directory `%s` doesn't exist", normalized_dir)
          goto continue
        end

        if not file.is_dir(normalized_dir) then
          log:warn("[Rules] Path `%s` is not a directory", normalized_dir)
          goto continue
        end

        local files = file.scan_directory(normalized_dir, { patterns = file_spec.files })
        add_paths(files)
        goto continue
      end
    end

    -- Handle glob patterns (e.g. "dir/**", "src/*.md")
    if tostring(path):match("[%*%?%[]") then
      local matches = vim.fn.glob(tostring(path), false, true) or {}
      for _, match in ipairs(matches) do
        local normalized = vim.fs.normalize(match)
        if file.exists(normalized) then
          if file.is_dir(normalized) then
            local files = file.scan_directory(normalized)
            add_paths(files)
          else
            add_path(normalized)
          end
        end
      end
      goto continue
    end

    -- Handle literal paths (files or directories)
    local normalized = vim.fs.normalize(path)

    if file.exists(normalized) then
      if file.is_dir(normalized) then
        local files = file.scan_directory(normalized)
        add_paths(files)
      else
        add_path(normalized)
      end
    end

    ::continue::
  end

  return collected_paths
end

---Read file contents from collected paths
---@param paths string[] List of file paths to read
---@return CodeCompanion.Chat.Rules.ProcessedFile[]
function Rules:read_files(paths)
  local files = {}

  for _, path in ipairs(paths) do
    if file.exists(path) and not file.is_dir(path) then
      local ok, content = pcall(file.read, path)

      if ok then
        -- Find the parser for this file
        local file_parser = nil
        for _, file_spec in ipairs(self.files) do
          if type(file_spec) == "table" and file_spec.path then
            local normalized_spec_path = vim.fs.normalize(file_spec.path)

            -- Check if this file matches the spec
            if file_spec.files then
              -- If files key exists, check if path is within the directory
              if path:find(normalized_spec_path, 1, true) == 1 then
                file_parser = file_spec.parser
                break
              end
            else
              -- Exact path match
              if path == normalized_spec_path then
                file_parser = file_spec.parser
                break
              end
            end
          end
        end

        table.insert(files, {
          name = path,
          content = content,
          path = path,
          filename = vim.fn.fnamemodify(path, ":t"),
          parser = file_parser,
        })
      end
    end
  end

  return files
end

---Parse the rules file contents
---@param files CodeCompanion.Chat.Rules.ProcessedFile[]
---@return CodeCompanion.Chat.Rules.ProcessedFile[]
function Rules:parse_files(files)
  vim.iter(files):each(function(f)
    local parsed = parsers.parse(f, self.parser)
    if parsed then
      f.system_prompt = parsed.system_prompt
      f.content = parsed.content
      f.meta = parsed.meta
    end
  end)

  return files
end

---Add rules as context to the chat
---@param chat CodeCompanion.Chat
function Rules:add_to_chat(chat)
  local included_files = {}

  for _, f in ipairs(self.processed) do
    if f.meta and f.meta.included_files then
      for _, i in ipairs(f.meta.included_files) do
        table.insert(included_files, i)
      end
    end
  end

  helpers.add_context(self.processed, chat)

  if #included_files > 0 then
    helpers.add_files_or_buffers(included_files, chat)
  end
end

---Process rules and add them to the chat
---@param args { chat: CodeCompanion.Chat }
---@return nil
function Rules:make(args)
  local paths = self:collect_files()
  local files = self:read_files(paths)
  self.processed = self:parse_files(files)
  self:add_to_chat(args.chat)
end

---Add rules to the chat based on the provided options (external API)
---@param chat CodeCompanion.Chat The chat instance
---@param args CodeCompanion.Chat.RulesArgs The rules options
---@return nil
function Rules.add_to_chat_from_config(chat, args)
  local rules = Rules.new(args)
  return rules:make({ chat = chat })
end

return Rules
