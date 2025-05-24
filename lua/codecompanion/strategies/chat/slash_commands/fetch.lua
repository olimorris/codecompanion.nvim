local Path = require("plenary.path")
local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")
local util_hash = require("codecompanion.utils.hash")

local fmt = string.format

local CONSTANTS = {
  NAME = "Fetch",
  CACHE_PATH = config.strategies.chat.slash_commands.fetch.opts.cache_path,
}

local providers = {
  ---The default provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  default = function(SlashCommand, urls)
    local default = require("codecompanion.providers.slash_commands.default")
    return default
      .new({
        output = function(selection)
          return SlashCommand:output(selection)
        end,
        SlashCommand = SlashCommand,
        title = CONSTANTS.PROMPT,
      })
      :find_files()
      :display()
  end,
}

---Format the output for the chat buffer
---@param url string
---@param text string
---@param opts table
---@return string
local function format_output(url, text, opts)
  local output = [[%s

<content>
%s
</content>]]

  if opts and opts.description then
    return fmt(output, opts.description, text)
  end

  return fmt(output, "Here is the output from " .. url .. " that I'm sharing with you:", text)
end

---Output the contents of the URL to the chat buffer
---@param chat CodeCompanion.Chat
---@param data table
---@param opts table
---@return nil
local function output(chat, data, opts)
  local id = "<url>" .. data.url .. "</url>"

  chat:add_message({
    role = config.constants.USER_ROLE,
    content = format_output(data.url, data.content, opts),
  }, { reference = id, visible = false })

  chat.references:add({
    source = "slash_command",
    name = "fetch",
    id = id,
  })

  if opts.silent then
    return
  end

  return util.notify(fmt("Added `%s` to the chat", data.url))
end

---Determine if the URL has already been cached
---@param hash string
---@return boolean
local function is_cached(hash)
  local p = Path:new(CONSTANTS.CACHE_PATH .. "/" .. hash)
  return p:exists()
end

---Read the cache for the URL
---@param chat CodeCompanion.Chat
---@param url string
---@param hash string
---@param opts table
---@return nil
local function read_cache(chat, url, hash, opts)
  local p = Path:new(CONSTANTS.CACHE_PATH .. "/" .. hash)
  local cache = p:read()

  log:debug("Fetch Slash Command: Restoring from cache for %s", url)

  return output(chat, {
    content = cache,
    url = url,
  }, opts)
end

---Write the cache for the URL
---@param hash string
---@param data string
---@return nil
local function write_cache(hash, data)
  local p = Path:new(CONSTANTS.CACHE_PATH .. "/" .. hash .. ".json")
  p.filename = p:expand()
  vim.fn.mkdir(CONSTANTS.CACHE_PATH, "p")
  p:touch({ parents = true })
  p:write(data or "", "w")
end

---Fetch the contents of a URL
---@param chat CodeCompanion.Chat
---@param adapter table
---@param url string
---@param opts table
---@return nil
local function fetch(chat, adapter, url, opts)
  adapter.env = {
    query = function()
      return url
    end,
  }

  log:debug("Fetch Slash Command: Fetching from %s", url)

  return client
    .new({
      adapter = adapter,
    })
    :request({
      url = url,
    }, {
      callback = function(err, data)
        if err then
          return log:error("Failed to fetch the URL, with error %s", err)
        end

        if data then
          local ok, body = pcall(vim.json.decode, data.body)
          if not ok then
            return log:error("Could not parse the JSON response")
          end
          if data.status == 200 then
            write_cache(
              util_hash.hash(url),
              vim.json.encode({
                url = url,
                timestamp = os.time(),
                data = body.data.text,
              })
            )
            return output(chat, {
              content = body.data.text,
              url = url,
            }, opts)
          else
            return log:error("Error %s - %s", data.status, body.data.text)
          end
        end
      end,
    })
end

---Prompt the user whether to load the URL from the cache
---@param chat CodeCompanion.Chat
---@param url string
---@param hash string
---@param adapter table
---@param opts table
---@param cb function
---@return nil
local function load_from_cache(chat, url, hash, adapter, opts, cb)
  return vim.ui.select({ "Yes", "No" }, {
    kind = "codecompanion.nvim",
    prompt = "Load the URL from the cache?",
  }, function(choice)
    if not choice then
      return cb
    end
    if choice == "Yes" then
      return read_cache(chat, url, hash, opts)
    end
    return fetch(chat, adapter, url, opts)
  end)
end

---Read the contents of the given file
---@param filepath string
---@return table
local function read_file(filepath)
  local file = Path:new(filepath)
  if not file:exists() then
    return log:error("No cached items found")
  end

  local content, err = file:read()
  if not content then
    log:error("Failed to read file: %s - %s", filepath, err)
    return { ok = false }
  end

  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    log:error("Failed to parse JSON: %s - %s", filepath, data)
    return { ok = false }
  end

  return { ok = true, data = data }
end

local function get_cached_files()
  local scan = require("plenary.scandir")
  local cache_dir = Path:new(CONSTANTS.CACHE_PATH):expand()

  -- Ensure cache directory exists
  if not Path:new(cache_dir):exists() then
    return {}
  end

  local cached_files = scan.scan_dir(cache_dir, {
    depth = 1,
    search_pattern = "%.json$",
  })

  local results = {}
  for _, filepath in ipairs(cached_files) do
    local file_data = read_file(filepath)
    if file_data.ok then
      local file = Path:new(filepath)
      table.insert(results, {
        filepath = filepath,
        filename = vim.fn.fnamemodify(file.filename, ":t"),
        url = file_data.data.url,
        timestamp = file_data.data.timestamp,
        data = file_data.data.data,
        display = string.format("[%s] %s", util.make_relative(file_data.data.timestamp), file_data.data.url),
      })
    end
  end

  -- Sort by timestamp (newest first)
  table.sort(results, function(a, b)
    return a.timestamp > b.timestamp
  end)

  return results
end

-- The different choices to load URLs in to the chat buffer
local choice = {
  URL = function(SlashCommand, _)
    return vim.ui.input({ prompt = "Enter the URL: " }, function(url)
      if #vim.trim(url or "") == 0 then
        return
      end

      return SlashCommand:output(url)
    end)
  end,
  Cache = function(SlashCommand, _)
    local cached_files = get_cached_files()

    if #cached_files == 0 then
      return util.notify("No cached URLs found", vim.log.levels.WARN)
    end

    return providers[SlashCommand.config.opts.provider](SlashCommand, cached_files)
  end,
}

---@class CodeCompanion.SlashCommand.Fetch: CodeCompanion.SlashCommand
local SlashCommand = {}

---@param args CodeCompanion.SlashCommandArgs
function SlashCommand.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommand })

  return self
end

---Execute the slash command
---@param SlashCommands CodeCompanion.SlashCommands
---@param opts? table
---@return nil|string
function SlashCommand:execute(SlashCommands, opts)
  vim.ui.select({ "URL", "Cache" }, {
    prompt = "Select link source",
    kind = "codecompanion.nvim",
  }, function(selected)
    if not selected then
      return
    end
    return choice[selected](self, SlashCommands)
  end)
end

---Output the contents of the URL
---@param url string
---@param opts? table
---@return nil
function SlashCommand:output(url, opts)
  local ok, adapter = pcall(require, "codecompanion.adapters.non_llm." .. self.config.opts.adapter)
  if not ok then
    ok, adapter = pcall(loadfile, self.config.opts.provider)
  end
  if not ok or not adapter then
    return log:error("Failed to load the adapter for the fetch Slash Command")
  end

  opts = opts or {}

  if type(adapter) == "function" then
    adapter = adapter()
  end

  adapter = adapters.resolve(adapter)
  if not adapter then
    return log:error("Failed to load the adapter for the fetch Slash Command")
  end

  local function call_fetch()
    return fetch(self.Chat, adapter, url, opts)
  end

  local hash = util_hash.hash(url)

  if opts and opts.ignore_cache then
    log:debug("Fetch Slash Command: Ignoring cache")
    return call_fetch()
  end
  if opts and opts.auto_restore_cache and is_cached(hash) then
    log:debug("Fetch Slash Command: Auto restoring from cache")
    return read_cache(self.Chat, url, hash, opts)
  end

  return call_fetch()
end

return SlashCommand
