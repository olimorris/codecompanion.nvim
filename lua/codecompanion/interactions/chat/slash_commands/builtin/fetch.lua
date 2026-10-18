local Path = require("plenary.path")

local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")
local hash_utils = require("codecompanion.utils.hash")
local log = require("codecompanion.utils.log")
local picker = require("codecompanion.providers.slash_commands.picker")
local utils = require("codecompanion.utils")

local fmt = string.format

local CONSTANTS = {
  NAME = "Fetch",
  CACHE_PATH = config.interactions.chat.slash_commands.fetch.opts.cache_path,
  SYNC_TIMEOUT = 10000,
}

---Get the cached URLs from the directory
---@return table
local function get_cached_files()
  local scan = require("plenary.scandir")
  local cache_dir = Path:new(CONSTANTS.CACHE_PATH):expand()

  if not Path:new(cache_dir):exists() then
    return {}
  end

  local cache = scan.scan_dir(cache_dir, {
    depth = 1,
    search_pattern = "%.json$",
  })

  local urls = vim
    .iter(cache)
    :map(function(f)
      local file = Path:new(f):read()
      local content = vim.json.decode(file)
      return {
        content = content.data,
        url = content.url,
        timestamp = content.timestamp,
      }
    end)
    :totable()

  -- Sort by timestamp (newest first)
  table.sort(urls, function(a, b)
    return a.timestamp > b.timestamp
  end)

  return urls
end

---Format the output for the chat buffer
---@param url string
---@param text string
---@return string
local function format_output(url, text)
  local output = [[<attachment url="%s">%s</attachment>]]

  return fmt(output, url, text)
end

---Output the contents of the URL to the chat buffer @param chat CodeCompanion.Chat
---@param chat CodeCompanion.Chat
---@param opts { url: string, content: string, silent?: boolean }
---@return nil
local function output(chat, opts)
  local id = "<url>" .. opts.url .. "</url>"

  chat:add_message({
    role = config.constants.USER_ROLE,
    content = format_output(opts.url, opts.content),
  }, { context = { id = id, url = opts.url }, visible = false })

  chat.context:add({
    source = "slash_command",
    name = "fetch",
    id = id,
  })

  if opts.silent then
    return
  end

  return utils.notify(fmt("Added `%s` to the chat", opts.url))
end

local providers = picker.build_list_pickers({
  prompt = "Select a cached URL",
  empty_message = "No cached URLs found",
  preview = false,
  output = function(SlashCommand, item)
    return output(SlashCommand.Chat, item)
  end,
  items = function()
    return vim.tbl_map(function(file)
      return {
        name = utils.make_relative(file.timestamp),
        description = file.url,
        url = file.url,
        content = file.content,
      }
    end, get_cached_files())
  end,
})

---Determine if the URL has already been cached
---@param hash string
---@return boolean
local function is_cached(hash)
  local p = Path:new(CONSTANTS.CACHE_PATH .. "/" .. hash)
  return p:exists()
end

---Read the cache for the URL
---@param chat CodeCompanion.Chat
---@param opts { url: string, hash: string, silent?: boolean }
---@return nil
local function read_cache(chat, opts)
  local p = Path:new(CONSTANTS.CACHE_PATH .. "/" .. opts.hash)
  local cache = p:read()

  log:debug("Fetch Slash Command: Restoring from cache for %s", opts.url)

  return output(chat, {
    content = cache,
    url = opts.url,
    silent = opts.silent,
  })
end

---Write the cache for the URL
---@param opts { hash: string, data: string }
---@return nil
local function write_cache(opts)
  local p = Path:new(CONSTANTS.CACHE_PATH .. "/" .. opts.hash .. ".json")
  p.filename = p:expand()
  vim.fn.mkdir(CONSTANTS.CACHE_PATH, "p")
  p:touch({ parents = true })
  p:write(opts.data or "", "w")
end

---Cache a fetched URL so that a later request can be served from disk
---@param opts { url: string, content: string }
---@return nil
local function cache_response(opts)
  local hash = hash_utils.hash(opts.url)
  write_cache({
    hash = hash,
    data = vim.json.encode({
      url = opts.url,
      hash = hash,
      timestamp = os.time(),
      data = opts.content,
    }),
  })
end

---Fetch the contents of a URL
---@param chat CodeCompanion.Chat
---@param opts { adapter: table, url: string, silent?: boolean }
---@return nil
local function fetch(chat, opts)
  local url = opts.url
  log:debug("Fetch Slash Command: Fetching from %s", url)

  -- Make sure that we don't modify the original adapter
  local adapter = vim.deepcopy(opts.adapter)
  adapter.methods.slash_commands.fetch.setup(adapter, { url = url })

  return client
    .new({
      adapter = adapter,
    })
    :request({ url = url }, {
      callback = function(err, data)
        if err then
          return log:error("Failed to fetch the URL, with error %s", err)
        end

        if data then
          local body = adapter.methods.slash_commands.fetch.callback(adapter, data)

          if body.status == "error" then
            return log:error("Error fetching URL: %s", body.content)
          end

          output(chat, {
            content = body.content,
            url = url,
            silent = opts.silent,
          })

          -- Cache the response
          -- TODO: Get an LLM to create summary
          vim.ui.select({ "Yes", "No" }, {
            prompt = "Do you want to cache this URL?",
            kind = "codecompanion.nvim",
          }, function(selected)
            if selected == "Yes" then
              cache_response({ url = url, content = body.content })
            end
          end)
        end
      end,
    })
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
  Cache = function(SlashCommand, SlashCommands)
    return SlashCommands:set_provider(SlashCommand, providers)
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
  local cached_files = get_cached_files()
  local options = { "URL" }
  if #cached_files > 0 then
    table.insert(options, "Cache")
  end

  if #options == 1 then
    return choice[options[1]](self, SlashCommands)
  end

  vim.ui.select(options, {
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
  opts = opts or {}

  local adapter = adapters.resolve(self.config.opts.adapter)
  if not adapter then
    return log:error("Could not resolve adapter for the fetch slash command")
  end

  local function call_fetch()
    return fetch(self.Chat, { adapter = adapter, url = url, silent = opts.silent })
  end

  local hash = hash_utils.hash(url)

  if opts and opts.ignore_cache then
    log:debug("Fetch Slash Command: Ignoring cache")
    return call_fetch()
  end
  if opts and opts.auto_restore_cache and is_cached(hash) then
    log:debug("Fetch Slash Command: Auto restoring from cache")
    return read_cache(self.Chat, { url = url, hash = hash, silent = opts.silent })
  end

  return call_fetch()
end

---Fetch a URL and add its contents to the chat buffer, blocking until it resolves
---@param opts { chat: CodeCompanion.Chat, url: string, cache?: boolean }
---@return boolean attached
function SlashCommand.fetch_sync(opts)
  local adapter = adapters.resolve(config.interactions.chat.slash_commands.fetch.opts.adapter)
  if not adapter then
    log:error("Could not resolve adapter for the fetch slash command")
    return false
  end

  adapter = vim.deepcopy(adapter)
  adapter.methods.slash_commands.fetch.setup(adapter, { url = opts.url })

  local done = false
  local response
  client.new({ adapter = adapter }):request({ url = opts.url }, {
    callback = function(err, data)
      done = true
      if err then
        return log:error("Failed to fetch the URL, with error %s", err)
      end
      if data then
        response = adapter.methods.slash_commands.fetch.callback(adapter, data)
      end
    end,
  })

  -- Waiting on the adapter's own callback keeps CLI-based adapters like markitdown working
  local finished, reason = vim.wait(CONSTANTS.SYNC_TIMEOUT, function()
    return done
  end, 100)
  if not finished then
    -- vim.wait reports -2 when the user presses a key, which is their way out of a slow fetch
    log:error("%s fetching %s", reason == -2 and "Cancelled" or "Timed out", opts.url)
    return false
  end

  if not response or response.status == "error" then
    log:error("Error fetching URL: %s", response and response.content or opts.url)
    return false
  end

  if opts.cache ~= false then
    cache_response({ url = opts.url, content = response.content })
  end
  output(opts.chat, { url = opts.url, content = response.content, silent = true })

  return true
end

return SlashCommand
